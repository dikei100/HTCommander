/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/data_broker_client.dart';

/// Manages a TCP/TLS connection to the Winlink CMS gateway (server.winlink.org:8773)
/// for relaying Winlink protocol traffic between a BBS radio client and the internet gateway.
/// The relay logs in using the connecting station's callsign, obtains the ;PQ: challenge,
/// and then transparently relays all Winlink B2F protocol traffic.
///
/// Port of HTCommander.Core/WinLink/WinlinkGatewayRelay.cs
class WinlinkGatewayRelay {
  final int deviceId;
  final DataBrokerClient _broker;
  final String server;
  final int port;
  final bool useTls;

  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;
  bool _running = false;
  bool _disposed = false;

  /// The ;PQ: challenge string received from the CMS gateway during login.
  /// Null if no challenge was received.
  String? pqChallenge;

  /// The [WL2K-...] banner string received from the CMS gateway.
  String? wl2kBanner;

  /// Whether the relay is currently connected to the CMS gateway.
  bool get isConnected => _socket != null && _running;

  /// When true, incoming data is forwarded as raw binary via [onBinaryDataReceived].
  /// When false, incoming data is parsed as lines and forwarded via [onLineReceived].
  bool binaryMode = false;

  /// Fired when line-based data is received from the CMS gateway.
  void Function(String line)? onLineReceived;

  /// Fired when raw binary data is received from the CMS gateway.
  void Function(Uint8List data)? onBinaryDataReceived;

  /// Fired when the CMS gateway connection is lost or closed.
  void Function()? onDisconnected;

  WinlinkGatewayRelay(
    this.deviceId,
    this._broker, {
    this.server = 'server.winlink.org',
    this.port = 8773,
    this.useTls = true,
  });

  /// Connects to the CMS gateway and performs the initial login handshake
  /// using the specified station callsign. Returns true if the connection
  /// and login succeed and a session prompt is received.
  Future<bool> connectAsync(String stationCallsign,
      {int timeoutMs = 15000}) async {
    try {
      _broker.logInfo(
          '[BBS/$deviceId/Relay] Connecting to CMS gateway $server:$port for station $stationCallsign');

      // Connect with timeout
      Socket rawSocket;
      try {
        rawSocket = await Socket.connect(
          server,
          port,
          timeout: Duration(milliseconds: timeoutMs),
        );
      } catch (e) {
        _broker.logError('[BBS/$deviceId/Relay] Connection timed out');
        _cleanupSocket();
        return false;
      }

      // Upgrade to TLS if required
      if (useTls) {
        try {
          _socket = await SecureSocket.secure(
            rawSocket,
            host: server,
            onBadCertificate: (X509Certificate cert) {
              _broker.logError(
                  '[BBS/$deviceId/Relay] Certificate validation error');
              return false;
            },
          );
        } catch (e) {
          _broker.logError('[BBS/$deviceId/Relay] TLS authentication failed');
          rawSocket.destroy();
          _cleanupSocket();
          return false;
        }
      } else {
        _socket = rawSocket;
      }

      _running = true;

      // Perform the login handshake synchronously (read prompts, send responses)
      final handshakeOk = await _performHandshake(stationCallsign, timeoutMs);
      if (!handshakeOk) {
        _broker.logError('[BBS/$deviceId/Relay] Handshake failed');
        disconnect();
        return false;
      }

      _broker.logInfo(
          '[BBS/$deviceId/Relay] Connected and handshake complete. PQ=${pqChallenge ?? "(none)"}');

      // Start the receive loop for ongoing relay
      _receiveLoop();

      return true;
    } catch (e) {
      _broker.logError('[BBS/$deviceId/Relay] Connection failed');
      _cleanupSocket();
      return false;
    }
  }

  /// Reads lines from the CMS gateway during the initial login, handling the
  /// "Callsign :", "Password :", [WL2K-...] banner, ;PQ: challenge, and > prompt.
  Future<bool> _performHandshake(
      String stationCallsign, int timeoutMs) async {
    final lineBuffer = StringBuffer();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    bool gotPrompt = false;

    // Use a completer + stream subscription for deadline-based reads
    final completer = Completer<bool>();

    final subscription = _socket!.listen(
      (Uint8List data) {
        if (completer.isCompleted) return;

        final chunk = utf8.decode(data, allowMalformed: true);
        lineBuffer.write(chunk);

        // Process complete lines
        var accumulated = lineBuffer.toString();
        while (true) {
          final crIdx = accumulated.indexOf('\r');
          final nlIdx = accumulated.indexOf('\n');
          int lineEnd = -1;
          int skipLen = 0;

          if (crIdx >= 0 && nlIdx >= 0) {
            if (crIdx < nlIdx) {
              lineEnd = crIdx;
              skipLen = (nlIdx == crIdx + 1) ? 2 : 1;
            } else {
              lineEnd = nlIdx;
              skipLen = 1;
            }
          } else if (crIdx >= 0) {
            lineEnd = crIdx;
            skipLen = 1;
          } else if (nlIdx >= 0) {
            lineEnd = nlIdx;
            skipLen = 1;
          } else {
            break;
          }

          final line = accumulated.substring(0, lineEnd);
          accumulated = accumulated.substring(lineEnd + skipLen);
          lineBuffer.clear();
          lineBuffer.write(accumulated);

          _broker.logInfo('[BBS/$deviceId/Relay] CMS << $line');

          // Handle prompts
          final trimmed = line.trim();

          if (trimmed.toLowerCase() == 'callsign :') {
            _broker.logInfo(
                '[BBS/$deviceId/Relay] Sending callsign: $stationCallsign');
            _sendRaw('$stationCallsign\r');
            continue;
          }

          if (trimmed.toLowerCase() == 'password :') {
            _broker.logInfo('[BBS/$deviceId/Relay] Sending password');
            _sendRaw('CMSTelnet\r');
            continue;
          }

          // Capture [WL2K-...] banner
          if (trimmed.startsWith('[WL2K-') && trimmed.endsWith(r'$]')) {
            wl2kBanner = trimmed;
            _broker.logInfo(
                '[BBS/$deviceId/Relay] Got WL2K banner: $wl2kBanner');
            continue;
          }

          // Capture ;PQ: challenge
          if (trimmed.startsWith(';PQ:')) {
            pqChallenge = trimmed.substring(4).trim();
            _broker.logInfo(
                '[BBS/$deviceId/Relay] Got PQ challenge: $pqChallenge');
            continue;
          }

          // Check for session prompt (ends with >)
          if (trimmed.endsWith('>')) {
            gotPrompt = true;
            break;
          }
        }

        if (gotPrompt && !completer.isCompleted) {
          completer.complete(true);
        }
      },
      onError: (error) {
        _broker.logError('[BBS/$deviceId/Relay] Handshake read error');
        if (!completer.isCompleted) completer.complete(false);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(false);
      },
      cancelOnError: false,
    );

    // Set up timeout
    final timer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) completer.complete(false);
    });

    final result = await completer.future;

    timer.cancel();
    // Pause the subscription so _receiveLoop can set up its own listener
    await subscription.cancel();

    // If we got a deadline timeout, check if somehow the prompt arrived
    if (!result && DateTime.now().isAfter(deadline)) {
      return gotPrompt;
    }

    return result;
  }

  /// Background receive loop that forwards incoming CMS data to the BBS session.
  void _receiveLoop() {
    final lineBuffer = StringBuffer();

    _socketSubscription = _socket!.listen(
      (Uint8List data) {
        if (binaryMode) {
          onBinaryDataReceived?.call(Uint8List.fromList(data));
        } else {
          // Parse into lines and forward
          final chunk = utf8.decode(data, allowMalformed: true);
          final normalized =
              chunk.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
          lineBuffer.write(normalized);

          final buffered = lineBuffer.toString();
          final lines = buffered.split('\r');

          // Keep the last element (may be incomplete)
          lineBuffer.clear();
          if (lines.isNotEmpty) {
            lineBuffer.write(lines.last);
          }

          // Process all complete lines (all except the last)
          for (int i = 0; i < lines.length - 1; i++) {
            final line = lines[i];
            if (line.isEmpty) continue;
            _broker.logInfo('[BBS/$deviceId/Relay] CMS << $line');
            onLineReceived?.call(line);
          }
        }
      },
      onError: (error) {
        if (_running) {
          _broker.logError('[BBS/$deviceId/Relay] Receive error');
        }
        _onConnectionClosed();
      },
      onDone: () {
        _onConnectionClosed();
      },
      cancelOnError: false,
    );
  }

  /// Handles connection closure detected by the receive loop.
  void _onConnectionClosed() {
    if (_running) {
      _broker.logInfo('[BBS/$deviceId/Relay] CMS connection closed');
      _running = false;
      _cleanupSocket();
      onDisconnected?.call();
    }
  }

  /// Sends a line to the CMS gateway (appends \r).
  void sendLine(String line) {
    if (!isConnected) return;
    _broker.logInfo('[BBS/$deviceId/Relay] CMS >> $line');
    _sendRaw('$line\r');
  }

  /// Sends raw binary data to the CMS gateway.
  void sendBinary(Uint8List data) {
    if (!isConnected) return;
    try {
      _socket!.add(data);
    } catch (e) {
      _broker.logError('[BBS/$deviceId/Relay] Binary send error');
      disconnect();
    }
  }

  /// Sends raw string data to the CMS gateway (no \r appended).
  void _sendRaw(String data) {
    if (!isConnected) return;
    try {
      _socket!.add(utf8.encode(data));
    } catch (e) {
      _broker.logError('[BBS/$deviceId/Relay] Send error');
      disconnect();
    }
  }

  /// Disconnects from the CMS gateway.
  void disconnect() {
    if (!_running && _socket == null) return;
    _broker.logInfo('[BBS/$deviceId/Relay] Disconnecting from CMS gateway');
    _running = false;
    _cleanupSocket();
    onDisconnected?.call();
  }

  /// Cleans up the TCP socket and stream subscription.
  void _cleanupSocket() {
    try {
      _socketSubscription?.cancel();
      _socketSubscription = null;
      _socket?.destroy();
      _socket = null;
    } catch (_) {}
  }

  /// Disposes the relay and releases all resources.
  void dispose() {
    if (!_disposed) {
      _running = false;
      _cleanupSocket();
      _broker.dispose();
      _disposed = true;
    }
  }
}
