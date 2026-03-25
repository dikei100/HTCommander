import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../platform/bluetooth_service.dart';
import '../../radio/gaia_protocol.dart';
import 'windows_native_methods.dart';

/// Windows Bluetooth transport using Winsock2 RFCOMM sockets via dart:ffi.
///
/// Strategy: Probe RFCOMM channels 1-30, send GAIA GET_DEV_ID on each,
/// and use the first channel that responds with a valid GAIA header.
/// Windows handles ACL connection automatically — no bluetoothctl equivalent.
///
/// The blocking connection + read loop runs in a separate Dart Isolate so the
/// main isolate UI thread is never blocked.
class WindowsRadioBluetooth extends RadioBluetoothTransport {
  final String _macAddress;
  bool _connected = false;
  Isolate? _isolate;
  SendPort? _toIsolate;
  StreamSubscription<dynamic>? _fromIsolateSub;

  WindowsRadioBluetooth(this._macAddress);

  @override
  bool get isConnected => _connected;

  @override
  void connect() {
    if (_connected || _isolate != null) return;

    final receivePort = ReceivePort();
    _fromIsolateSub = receivePort.listen(_handleIsolateMessage);

    final mac =
        _macAddress.replaceAll(':', '').replaceAll('-', '').toUpperCase();

    Isolate.spawn(
      _isolateEntry,
      _IsolateStartArgs(receivePort.sendPort, mac),
    ).then((isolate) {
      _isolate = isolate;
    }).catchError((Object error) {
      _fromIsolateSub?.cancel();
      _fromIsolateSub = null;
      onDataReceived?.call(
        Exception('Failed to spawn isolate: $error'),
        null,
      );
    });
  }

  @override
  void disconnect() {
    _connected = false;
    if (_toIsolate != null) {
      _toIsolate!.send({'cmd': 'disconnect'});
      // Give isolate time to close the socket cleanly before killing.
      Future.delayed(const Duration(seconds: 1), _cleanup);
    } else {
      _cleanup();
    }
  }

  @override
  void enqueueWrite(int expectedResponse, Uint8List cmdData) {
    if (!_connected || _toIsolate == null) return;
    final frame = GaiaProtocol.encode(cmdData);
    _toIsolate!.send({'cmd': 'write', 'data': frame});
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      _toIsolate = message;
      return;
    }
    if (message is! Map<String, dynamic>) return;

    final event = message['event'] as String?;
    switch (event) {
      case 'connected':
        _connected = true;
        onConnected?.call();
      case 'data':
        final payload = message['payload'] as Uint8List;
        onDataReceived?.call(null, payload);
      case 'error':
        final msg = message['msg'] as String? ?? 'Unknown error';
        onDataReceived?.call(Exception(msg), null);
      case 'log':
        // ignore: avoid_print
        print('[BT-Isolate] ${message['msg'] ?? ''}');
      case 'disconnected':
        _connected = false;
        _cleanup();
        onDataReceived?.call(
          Exception(message['msg'] as String? ?? 'Disconnected'),
          null,
        );
    }
  }

  void _cleanup() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toIsolate = null;
    _fromIsolateSub?.cancel();
    _fromIsolateSub = null;
  }

  // ---------------------------------------------------------------------------
  // Isolate entry point — all blocking I/O happens here
  // ---------------------------------------------------------------------------

  static Future<void> _isolateEntry(_IsolateStartArgs args) async {
    final toMain = args.mainPort;
    final receivePort = ReceivePort();
    toMain.send(receivePort.sendPort);

    final mac = args.mac;
    final macColon = _formatMacColon(mac);

    // Initialize Winsock in this isolate
    final wsaResult = initializeWinsock();
    if (wsaResult != 0) {
      toMain.send(<String, dynamic>{
        'event': 'disconnected',
        'msg': 'WSAStartup failed with error: $wsaResult',
      });
      return;
    }

    // State
    var running = true;
    var sock = invalidSocket;

    // Write queue: filled by receivePort listener, drained by read loop.
    final writeQueue = <Uint8List>[];

    // Listen for commands from the main isolate
    receivePort.listen((dynamic message) {
      if (message is! Map<String, dynamic>) return;
      final cmd = message['cmd'] as String?;
      switch (cmd) {
        case 'write':
          if (sock == invalidSocket) return;
          final data = message['data'] as Uint8List;
          writeQueue.add(data);
        case 'disconnect':
          running = false;
      }
    });

    // Connection with retries
    for (int attempt = 1; attempt <= 3 && running; attempt++) {
      try {
        _debug(toMain, 'Connecting to $macColon (attempt $attempt/3)...');

        // Windows handles ACL connection automatically — no bluetoothctl step.
        // Probe channels 1-30 for GAIA response.
        _debug(toMain, 'Probing RFCOMM channels 1-30...');
        sock = _probeChannels(macColon, toMain);

        if (sock != invalidSocket) {
          _debug(toMain, 'Connected on socket=$sock');
          break;
        }

        _debug(toMain, 'Attempt $attempt failed — no GAIA-responsive channel');
        if (attempt < 3 && running) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      } catch (e, st) {
        _debug(toMain, 'Attempt $attempt error: $e\n$st');
        if (sock != invalidSocket) {
          WindowsNativeMethods.closesocket(sock);
          sock = invalidSocket;
        }
        if (attempt < 3 && running) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    }

    if (sock == invalidSocket) {
      toMain.send(<String, dynamic>{
        'event': 'disconnected',
        'msg': 'Unable to connect — no GAIA-responsive channel found',
      });
      return;
    }

    // Set non-blocking mode via ioctlsocket(FIONBIO)
    final mode = calloc<ffi.Uint32>();
    mode.value = 1; // Non-blocking
    final ioctlResult =
        WindowsNativeMethods.ioctlsocket(sock, fionbio, mode);
    calloc.free(mode);

    if (ioctlResult == socketError) {
      final err = WindowsNativeMethods.wsaGetLastError();
      WindowsNativeMethods.closesocket(sock);
      toMain.send(<String, dynamic>{
        'event': 'disconnected',
        'msg': 'Failed to set non-blocking mode: WSA=$err',
      });
      return;
    }

    // Notify main isolate that connection is established
    toMain.send(<String, dynamic>{'event': 'connected'});

    // Read loop (async — yields to event loop so write queue gets filled)
    await _runReadLoop(sock, toMain, writeQueue, () => running);

    // Cleanup
    WindowsNativeMethods.closesocket(sock);
    sock = invalidSocket;
    toMain.send(<String, dynamic>{
      'event': 'disconnected',
      'msg': 'Connection closed',
    });
  }

  /// Async read loop that yields to the isolate event loop on idle cycles.
  ///
  /// Critical: Dart isolates are single-threaded. Using synchronous sleep()
  /// would block the event loop, preventing the ReceivePort listener from
  /// processing write commands. By using await Future.delayed() instead,
  /// we yield to the event loop which processes queued writes between reads.
  static Future<void> _runReadLoop(
    int sock,
    SendPort toMain,
    List<Uint8List> writeQueue,
    bool Function() isRunning,
  ) async {
    final accumulator = Uint8List(4096);
    var accPtr = 0;
    var accLen = 0;
    final readBufSize = 1024;
    final readBuf = calloc<ffi.Uint8>(readBufSize);

    try {
      while (isRunning()) {
        // Drain write queue — process pending writes from the main isolate
        while (writeQueue.isNotEmpty) {
          final data = writeQueue.removeAt(0);
          _writeAll(sock, data);
        }

        final bytesRead =
            WindowsNativeMethods.recv(sock, readBuf, readBufSize, 0);

        if (bytesRead < 0) {
          final err = WindowsNativeMethods.wsaGetLastError();
          if (err == wsaeWouldBlock || err == wsaeInProgress) {
            // No data available — yield to event loop (processes writes)
            await Future<void>.delayed(const Duration(milliseconds: 50));
            continue;
          }
          // Real error
          toMain.send(<String, dynamic>{
            'event': 'log',
            'msg': 'Read error: WSA=$err',
          });
          break;
        }

        if (bytesRead == 0) {
          // Remote closed connection
          toMain.send(<String, dynamic>{
            'event': 'log',
            'msg': 'Remote closed connection (recv returned 0)',
          });
          break;
        }

        // Copy native buffer into accumulator
        int space = accumulator.length - (accPtr + accLen);
        if (space <= 0) {
          accPtr = 0;
          accLen = 0;
          space = accumulator.length;
        }

        final toCopy = bytesRead <= space ? bytesRead : space;
        for (int i = 0; i < toCopy; i++) {
          accumulator[accPtr + accLen + i] = readBuf[i];
        }
        accLen += toCopy;

        if (accLen < 8) continue;

        // Decode GAIA frames
        while (true) {
          final (consumed, cmd) =
              GaiaProtocol.decode(accumulator, accPtr, accLen);
          if (consumed == 0) break;
          final skip = consumed < 0 ? accLen : consumed;
          accPtr += skip;
          accLen -= skip;
          if (cmd != null) {
            toMain.send(<String, dynamic>{'event': 'data', 'payload': cmd});
          }
          if (consumed < 0) break;
        }

        if (accLen == 0) accPtr = 0;
        if (accPtr > 2048) {
          accumulator.setRange(0, accLen, accumulator, accPtr);
          accPtr = 0;
        }
      }
    } finally {
      calloc.free(readBuf);
    }
  }

  // --- Connection helpers (run in isolate) ---

  static void _debug(SendPort toMain, String msg) {
    toMain.send(<String, dynamic>{'event': 'log', 'msg': msg});
  }

  static int _probeChannels(String macAddress, SendPort toMain) {
    for (int ch = 1; ch <= 30; ch++) {
      _debug(toMain, 'Probing channel $ch...');
      final sock = _createRfcommSocket(macAddress, ch, toMain);
      if (sock == invalidSocket) continue;

      try {
        if (_verifyGaiaResponse(sock, ch, toMain)) {
          _debug(toMain, 'Channel $ch: GAIA verified!');
          return sock;
        }
        _debug(toMain, 'Channel $ch: no GAIA response');
      } catch (e) {
        _debug(toMain, 'Channel $ch: verification error: $e');
      }

      WindowsNativeMethods.closesocket(sock);
    }
    return invalidSocket;
  }

  /// Sends GAIA GET_DEV_ID and checks for a valid FF 01 response.
  static bool _verifyGaiaResponse(int sock, int channel, SendPort toMain) {
    // Build GET_DEV_ID: group=BASIC(2), cmd=GET_DEV_ID(1)
    final gaiaCmd =
        GaiaProtocol.encode(Uint8List.fromList([0x00, 0x02, 0x00, 0x01]));

    final hexStr = gaiaCmd
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    _debug(toMain,
        'Ch $channel: sending GAIA GET_DEV_ID: $hexStr (${gaiaCmd.length} bytes)');

    // Write
    final writeBuf = calloc<ffi.Uint8>(gaiaCmd.length);
    try {
      for (int i = 0; i < gaiaCmd.length; i++) {
        writeBuf[i] = gaiaCmd[i];
      }
      final sent =
          WindowsNativeMethods.send(sock, writeBuf, gaiaCmd.length, 0);
      if (sent == socketError) {
        _debug(toMain,
            'Ch $channel: send failed WSA=${WindowsNativeMethods.wsaGetLastError()}');
        return false;
      }
      _debug(toMain, 'Ch $channel: sent $sent bytes');
    } finally {
      calloc.free(writeBuf);
    }

    // Poll for response with 5-second timeout using WSAPoll
    final pfd = calloc<WsaPollFd>();
    try {
      pfd.ref.fd = sock;
      pfd.ref.events = pollIn;
      pfd.ref.revents = 0;

      final pollResult = WindowsNativeMethods.wsaPoll(pfd, 1, 5000);
      _debug(toMain,
          'Ch $channel: WSAPoll=$pollResult, revents=0x${pfd.ref.revents.toRadixString(16)}');

      if (pollResult <= 0) {
        if (pollResult == socketError) {
          _debug(toMain,
              'Ch $channel: WSAPoll error=${WindowsNativeMethods.wsaGetLastError()}');
        }
        return false;
      }

      if ((pfd.ref.revents & (pollErr | pollHup)) != 0) {
        return false;
      }

      if ((pfd.ref.revents & pollIn) == 0) return false;
    } finally {
      calloc.free(pfd);
    }

    // Read response
    final readBuf = calloc<ffi.Uint8>(1024);
    try {
      final bytesRead = WindowsNativeMethods.recv(sock, readBuf, 1024, 0);
      if (bytesRead <= 0) {
        _debug(toMain,
            'Ch $channel: recv returned $bytesRead, WSA=${WindowsNativeMethods.wsaGetLastError()}');
        return false;
      }

      final respHex = List.generate(
        bytesRead > 32 ? 32 : bytesRead,
        (i) => readBuf[i].toRadixString(16).padLeft(2, '0').toUpperCase(),
      ).join(' ');
      _debug(toMain, 'Ch $channel: received $bytesRead bytes: $respHex');

      // Verify GAIA header: FF 01
      return bytesRead >= 2 && readBuf[0] == 0xFF && readBuf[1] == 0x01;
    } finally {
      calloc.free(readBuf);
    }
  }

  static int _createRfcommSocket(
      String macAddress, int channel, SendPort toMain) {
    final sock =
        WindowsNativeMethods.socket(afBth, sockStream, bthprotoRfcomm);
    if (sock == invalidSocket) {
      _debug(toMain,
          'socket() failed: WSA=${WindowsNativeMethods.wsaGetLastError()}');
      return invalidSocket;
    }

    final addr = buildSockaddrBth(macAddress, channel);
    try {
      final result = WindowsNativeMethods.connect(
          sock, addr.cast<ffi.Void>(), sockaddrBthSize);
      if (result == socketError) {
        final err = WindowsNativeMethods.wsaGetLastError();
        _debug(toMain, 'connect(ch=$channel) failed: WSA=$err');
        WindowsNativeMethods.closesocket(sock);
        return invalidSocket;
      }

      _debug(toMain, 'RFCOMM connected: socket=$sock, ch=$channel');
      return sock;
    } finally {
      calloc.free(addr);
    }
  }

  static void _writeAll(int sock, Uint8List data) {
    final buf = calloc<ffi.Uint8>(data.length);
    try {
      for (int i = 0; i < data.length; i++) {
        buf[i] = data[i];
      }

      var totalWritten = 0;
      while (totalWritten < data.length) {
        final written = WindowsNativeMethods.send(
          sock,
          buf + totalWritten,
          data.length - totalWritten,
          0,
        );
        if (written > 0) {
          totalWritten += written;
        } else if (written == socketError) {
          final err = WindowsNativeMethods.wsaGetLastError();
          if (err == wsaeWouldBlock || err == wsaeInProgress) {
            // Brief spin-wait — we're in the read loop which will yield soon
            continue;
          }
          return; // Real write error
        } else {
          return; // written == 0, unexpected
        }
      }
    } finally {
      calloc.free(buf);
    }
  }

  static String _formatMacColon(String mac) {
    final parts = <String>[];
    for (int i = 0; i < 6; i++) {
      parts.add(mac.substring(i * 2, i * 2 + 2));
    }
    return parts.join(':');
  }
}

/// Arguments passed to the isolate entry point.
class _IsolateStartArgs {
  final SendPort mainPort;
  final String mac;

  const _IsolateStartArgs(this.mainPort, this.mac);
}
