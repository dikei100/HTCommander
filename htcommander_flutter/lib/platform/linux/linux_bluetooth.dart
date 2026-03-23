import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../platform/bluetooth_service.dart';
import '../../radio/gaia_protocol.dart';
import 'native_methods.dart';

/// Linux Bluetooth transport using direct native RFCOMM sockets via dart:ffi.
///
/// Strategy: Use SDP to discover the SPP command channel, then connect with a
/// native RFCOMM socket and verify GAIA protocol response. Falls back to
/// probing channels 1-10 if SDP fails.
///
/// The blocking connection + read loop runs in a separate Dart Isolate so the
/// main isolate UI thread is never blocked.
class LinuxRadioBluetooth extends RadioBluetoothTransport {
  final String _macAddress;
  bool _connected = false;
  Isolate? _isolate;
  SendPort? _toIsolate;
  StreamSubscription<dynamic>? _fromIsolateSub;

  LinuxRadioBluetooth(this._macAddress);

  @override
  bool get isConnected => _connected;

  @override
  void connect() {
    if (_connected || _isolate != null) return;

    final receivePort = ReceivePort();
    _fromIsolateSub = receivePort.listen(_handleIsolateMessage);

    final mac = _macAddress.replaceAll(':', '').replaceAll('-', '').toUpperCase();

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
    _toIsolate?.send({'cmd': 'disconnect'});
    _cleanup();
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
        // Forward isolate debug messages to DataBroker log
        final msg = message['msg'] as String? ?? '';
        // Import not available here — use the onDataReceived with a special marker
        // Instead, just print to console for debugging
        // ignore: avoid_print
        print('[BT-Isolate] $msg');
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
    final bdaddr = parseMacAddress(mac);

    // State
    var running = true;
    var rfcommFd = -1;

    // Listen for commands from the main isolate
    receivePort.listen((dynamic message) {
      if (message is! Map<String, dynamic>) return;
      final cmd = message['cmd'] as String?;
      switch (cmd) {
        case 'write':
          if (rfcommFd < 0) return;
          final data = message['data'] as Uint8List;
          _writeAll(rfcommFd, data);
        case 'disconnect':
          running = false;
      }
    });

    // Connection with retries
    for (int attempt = 1; attempt <= 3 && running; attempt++) {
      try {
        _debug(toMain, 'Connecting to $macColon (attempt $attempt/3)...');

        // Step 1: ACL connect via bluetoothctl
        _debug(toMain, 'Step 1: ACL connect via bluetoothctl...');
        await _aclConnect(macColon, toMain);

        // Step 2: SDP discovery
        _debug(toMain, 'Step 2: SDP channel discovery...');
        final sppChannels = await _discoverSppChannels(macColon, toMain);

        if (sppChannels != null && sppChannels.isNotEmpty) {
          _debug(toMain, 'SDP found ${sppChannels.length} channel(s): $sppChannels');
          rfcommFd = _connectToGaiaChannel(bdaddr, sppChannels, toMain);
        } else {
          _debug(toMain, 'SDP discovery returned no channels');
        }

        // Step 3: Probe channels 1-10 if SDP failed
        if (rfcommFd < 0) {
          _debug(toMain, 'Step 3: Probing RFCOMM channels 1-10...');
          rfcommFd = _probeChannels(bdaddr, toMain);
        }

        if (rfcommFd >= 0) {
          _debug(toMain, 'Connected on fd=$rfcommFd');
          break;
        }

        _debug(toMain, 'Attempt $attempt failed — no GAIA-responsive channel');
        if (attempt < 3 && running) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      } catch (e, st) {
        _debug(toMain, 'Attempt $attempt error: $e\n$st');
        if (rfcommFd >= 0) {
          NativeMethods.close(rfcommFd);
          rfcommFd = -1;
        }
        if (attempt < 3 && running) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }

    if (rfcommFd < 0) {
      toMain.send(<String, dynamic>{
        'event': 'disconnected',
        'msg': 'Unable to connect — no GAIA-responsive channel found',
      });
      return;
    }

    // Set non-blocking mode
    final curFlags = NativeMethods.fcntl(rfcommFd, fGetfl);
    if (curFlags < 0) {
      NativeMethods.close(rfcommFd);
      toMain.send(<String, dynamic>{
        'event': 'disconnected',
        'msg': 'Failed to get socket flags',
      });
      return;
    }
    NativeMethods.fcntl3(rfcommFd, fSetfl, curFlags | oNonblock);

    // Notify main isolate that connection is established
    toMain.send(<String, dynamic>{'event': 'connected'});

    // Read loop
    _runReadLoop(rfcommFd, toMain, () => running);

    // Cleanup
    NativeMethods.close(rfcommFd);
    rfcommFd = -1;
    toMain.send(<String, dynamic>{
      'event': 'disconnected',
      'msg': 'Connection closed',
    });
  }

  static void _runReadLoop(
    int fd,
    SendPort toMain,
    bool Function() isRunning,
  ) {
    final accumulator = Uint8List(4096);
    var accPtr = 0;
    var accLen = 0;
    final readBufSize = 1024;
    final readBuf = calloc<Uint8>(readBufSize);

    try {
      while (isRunning()) {
        final bytesRead =
            NativeMethods.read(fd, readBuf.cast<Void>(), readBufSize);

        if (bytesRead < 0) {
          final err = NativeMethods.errno;
          if (err == eagain || err == eintr) {
            // No data available — sleep and retry
            sleep(const Duration(milliseconds: 50));
            continue;
          }
          // Real error
          break;
        }

        if (bytesRead == 0) {
          // Remote closed connection
          break;
        }

        // Copy native buffer into accumulator
        final space = accumulator.length - (accPtr + accLen);
        if (space <= 0) {
          accPtr = 0;
          accLen = 0;
        }

        // Ensure we don't overflow the accumulator
        final toCopy =
            bytesRead <= (accumulator.length - (accPtr + accLen))
                ? bytesRead
                : (accumulator.length - (accPtr + accLen));
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
            // Send decoded command to main isolate (Uint8List is transferable)
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

  static Future<void> _aclConnect(String macColon, SendPort toMain) async {
    try {
      final result = await Process.run('bluetoothctl', ['connect', macColon]);
      _debug(toMain, 'bluetoothctl connect: exit=${result.exitCode}, stdout=${(result.stdout as String).trim()}');
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (e) {
      _debug(toMain, 'bluetoothctl failed: $e (non-fatal)');
    }
  }

  static Future<List<int>?> _discoverSppChannels(String macColon, SendPort toMain) async {
    try {
      final result = await Process.run('sdptool', ['browse', macColon]);
      _debug(toMain, 'sdptool browse: exit=${result.exitCode}, output=${(result.stdout as String).length} bytes');
      if (result.exitCode != 0) {
        _debug(toMain, 'sdptool stderr: ${(result.stderr as String).trim()}');
        return null;
      }

      final output = result.stdout as String;
      if (output.isEmpty) return null;

      return _parseSdptoolOutput(output);
    } catch (e) {
      _debug(toMain, 'sdptool failed: $e');
      return null;
    }
  }

  static List<int> _parseSdptoolOutput(String output) {
    final sppChannels = <int>[];
    final allChannels = <int>[];
    final records = output.split('Service Name:');
    final channelRegex = RegExp(r'Channel:\s*(\d+)');

    for (final record in records) {
      final match = channelRegex.firstMatch(record);
      if (match == null) continue;

      final channel = int.tryParse(match.group(1)!);
      if (channel == null || channel < 1 || channel > 30) continue;

      final isSpp = record.contains('SPP Dev') ||
          record.contains('Serial Port') ||
          record.contains('00001101-0000-1000-8000-00805f9b34fb');

      if (isSpp) {
        sppChannels.add(channel);
      } else {
        allChannels.add(channel);
      }
    }

    return sppChannels.isNotEmpty ? sppChannels : allChannels;
  }

  static int _connectToGaiaChannel(List<int> bdaddr, List<int> channels, SendPort toMain) {
    for (final ch in channels) {
      _debug(toMain, 'Trying SDP channel $ch...');
      final fd = _createRfcommFd(bdaddr, ch, toMain);
      if (fd < 0) continue;

      try {
        if (_verifyGaiaResponse(fd, ch, toMain)) {
          _debug(toMain, 'Channel $ch: GAIA verified!');
          return fd;
        }
        _debug(toMain, 'Channel $ch: no GAIA response');
      } catch (e) {
        _debug(toMain, 'Channel $ch: verification error: $e');
      }

      NativeMethods.close(fd);
    }
    return -1;
  }

  static int _probeChannels(List<int> bdaddr, SendPort toMain) {
    for (int ch = 1; ch <= 10; ch++) {
      _debug(toMain, 'Probing channel $ch...');
      final fd = _createRfcommFd(bdaddr, ch, toMain);
      if (fd < 0) continue;

      try {
        if (_verifyGaiaResponse(fd, ch, toMain)) {
          _debug(toMain, 'Channel $ch: GAIA verified!');
          return fd;
        }
        _debug(toMain, 'Channel $ch: no GAIA response');
      } catch (e) {
        _debug(toMain, 'Channel $ch: verification error: $e');
      }

      NativeMethods.close(fd);
    }
    return -1;
  }

  /// Sends GAIA GET_DEV_ID and checks for a valid FF 01 response via poll().
  static bool _verifyGaiaResponse(int fd, int channel, SendPort toMain) {
    // Build GET_DEV_ID: group=BASIC(2), cmd=1
    final gaiaCmd =
        GaiaProtocol.encode(Uint8List.fromList([0x00, 0x02, 0x00, 0x01]));

    final writeBuf = calloc<Uint8>(gaiaCmd.length);
    try {
      for (int i = 0; i < gaiaCmd.length; i++) {
        writeBuf[i] = gaiaCmd[i];
      }
      final sent =
          NativeMethods.write(fd, writeBuf.cast<Void>(), gaiaCmd.length);
      if (sent < 0) return false;
    } finally {
      calloc.free(writeBuf);
    }

    // Poll for response with 3-second timeout
    final pfd = calloc<PollFd>();
    try {
      pfd.ref.fd = fd;
      pfd.ref.events = pollin;
      pfd.ref.revents = 0;

      final pollResult = NativeMethods.poll(pfd, 1, 3000);
      if (pollResult <= 0) return false;

      if ((pfd.ref.revents & (pollerr | pollhup | pollnval)) != 0) {
        return false;
      }

      if ((pfd.ref.revents & pollin) == 0) return false;
    } finally {
      calloc.free(pfd);
    }

    // Read response
    final readSize = 1024;
    final readBuf = calloc<Uint8>(readSize);
    try {
      final bytesRead =
          NativeMethods.read(fd, readBuf.cast<Void>(), readSize);
      if (bytesRead < 2) return false;

      // Verify GAIA header: FF 01
      return readBuf[0] == 0xFF && readBuf[1] == 0x01;
    } finally {
      calloc.free(readBuf);
    }
  }

  static int _createRfcommFd(List<int> bdaddr, int channel, SendPort toMain) {
    if (bdaddr.length < 6) return -1;

    final fd = NativeMethods.socket(afBluetooth, sockStream, btprotoRfcomm);
    if (fd < 0) {
      _debug(toMain, 'socket() failed: errno=${NativeMethods.errno}');
      return -1;
    }

    final addr = buildSockaddrRc(bdaddr, channel);

    // Block SIGPROF around connect() — Dart VM's profiler sends SIGPROF
    // which interrupts blocking syscalls with EINTR on RFCOMM sockets.
    final blockSet = calloc<Uint8>(sigsetSize);
    final oldSet = calloc<Uint8>(sigsetSize);

    try {
      NativeMethods.sigemptyset(blockSet);
      NativeMethods.sigaddset(blockSet, sigprof);
      NativeMethods.sigaddset(blockSet, sigalrm);
      NativeMethods.sigprocmask(sigBlock, blockSet, oldSet);

      final result = NativeMethods.connect(fd, addr.cast<Void>(), 10);

      // Restore signal mask immediately
      NativeMethods.sigprocmask(sigUnblock, blockSet, nullptr.cast<Uint8>());

      if (result == 0) {
        _debug(toMain, 'RFCOMM connected: fd=$fd, ch=$channel');
        return fd;
      }

      final err = NativeMethods.errno;
      _debug(toMain, 'connect(ch=$channel) failed: errno=$err');
      NativeMethods.close(fd);
      return -1;
    } finally {
      calloc.free(addr);
      calloc.free(blockSet);
      calloc.free(oldSet);
    }
  }

  static void _writeAll(int fd, Uint8List data) {
    final buf = calloc<Uint8>(data.length);
    try {
      for (int i = 0; i < data.length; i++) {
        buf[i] = data[i];
      }

      var totalWritten = 0;
      while (totalWritten < data.length) {
        final written = NativeMethods.write(
          fd,
          (buf.cast<Uint8>() + totalWritten).cast<Void>(),
          data.length - totalWritten,
        );
        if (written > 0) {
          totalWritten += written;
        } else if (written < 0) {
          final err = NativeMethods.errno;
          if (err == eagain || err == eintr) {
            sleep(const Duration(milliseconds: 5));
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
    // mac is already clean uppercase hex, e.g. "AABBCCDDEEFF"
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
