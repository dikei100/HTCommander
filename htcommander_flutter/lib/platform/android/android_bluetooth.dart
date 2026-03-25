import 'dart:async';

import 'package:flutter/services.dart';

import '../../platform/bluetooth_service.dart';
import '../../radio/gaia_protocol.dart';

/// Android Bluetooth RFCOMM transport using MethodChannel/EventChannel.
///
/// GAIA frame encoding/decoding stays in Dart. Only raw byte I/O goes through
/// the platform channel to Kotlin, which manages the BluetoothSocket on a
/// background thread.
///
/// Raw bytes from the socket are accumulated and decoded into GAIA commands
/// before being delivered to [onDataReceived], matching the Linux isolate
/// behavior.
class AndroidRadioBluetooth extends RadioBluetoothTransport {
  static const _methodChannel = MethodChannel('com.htcommander/bluetooth');
  static const _eventChannel = EventChannel('com.htcommander/bluetooth_events');

  final String _macAddress;
  bool _connected = false;
  StreamSubscription<dynamic>? _eventSub;

  // GAIA frame accumulator — mirrors the Linux isolate's decode loop.
  // Raw socket bytes may arrive in chunks that don't align with GAIA frame
  // boundaries, so we accumulate and decode incrementally.
  final _accumulator = Uint8List(8192);
  int _accPtr = 0;
  int _accLen = 0;

  AndroidRadioBluetooth(this._macAddress);

  @override
  bool get isConnected => _connected;

  @override
  void connect() {
    if (_connected) return;

    // Reset accumulator
    _accPtr = 0;
    _accLen = 0;

    // Subscribe to events from Kotlin side
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object error) {
        onDataReceived?.call(Exception('Event stream error: $error'), null);
      },
      onDone: () {
        if (_connected) {
          _connected = false;
          onDataReceived?.call(Exception('Event stream closed'), null);
        }
      },
    );

    // Initiate connection on Kotlin side
    final mac = _macAddress.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    _methodChannel.invokeMethod<void>('connect', {'mac': mac}).catchError(
      (Object error) {
        onDataReceived?.call(
          Exception('Connection failed: $error'),
          null,
        );
      },
    );
  }

  @override
  void disconnect() {
    _connected = false;
    _methodChannel.invokeMethod<void>('disconnect').catchError((_) {});
    // Delay cleanup to let Kotlin close the socket cleanly,
    // matching the Linux isolate's 1-second delay pattern.
    Future.delayed(const Duration(seconds: 1), _cleanup);
  }

  @override
  void enqueueWrite(int expectedResponse, Uint8List cmdData) {
    if (!_connected) return;
    final frame = GaiaProtocol.encode(cmdData);
    _methodChannel
        .invokeMethod<void>('write', {'data': frame})
        .catchError((_) {});
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final map = Map<String, dynamic>.from(event);
    final type = map['event'] as String?;

    switch (type) {
      case 'connected':
        _connected = true;
        onConnected?.call();
      case 'data':
        final raw = map['payload'] as Uint8List;
        _decodeGaiaFrames(raw);
      case 'log':
        // Debug messages from Kotlin — forward to console
        // ignore: avoid_print
        print('[BT-Android] ${map['msg'] ?? ''}');
      case 'error':
        final msg = map['msg'] as String? ?? 'Unknown error';
        onDataReceived?.call(Exception(msg), null);
      case 'disconnected':
        _connected = false;
        _cleanup();
        onDataReceived?.call(
          Exception(map['msg'] as String? ?? 'Disconnected'),
          null,
        );
    }
  }

  /// Accumulates raw socket bytes and decodes GAIA frames, matching the
  /// Linux isolate's frame reassembly logic.
  void _decodeGaiaFrames(Uint8List raw) {
    // Compact accumulator if pointer has advanced past half
    if (_accPtr > 4096) {
      _accumulator.setRange(0, _accLen, _accumulator, _accPtr);
      _accPtr = 0;
    }

    // Append new data
    final space = _accumulator.length - (_accPtr + _accLen);
    final toCopy = raw.length <= space ? raw.length : space;
    _accumulator.setRange(_accPtr + _accLen, _accPtr + _accLen + toCopy, raw);
    _accLen += toCopy;

    if (_accLen < 8) return;

    // Decode complete GAIA frames
    while (true) {
      final (consumed, cmd) =
          GaiaProtocol.decode(_accumulator, _accPtr, _accLen);
      if (consumed == 0) break; // need more data
      final skip = consumed < 0 ? _accLen : consumed;
      _accPtr += skip;
      _accLen -= skip;
      if (cmd != null) {
        onDataReceived?.call(null, cmd);
      }
      if (consumed < 0) break; // invalid header, skip all
    }

    if (_accLen == 0) _accPtr = 0;
  }

  void _cleanup() {
    _eventSub?.cancel();
    _eventSub = null;
    _accPtr = 0;
    _accLen = 0;
  }
}
