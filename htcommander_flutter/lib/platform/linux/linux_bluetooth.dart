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
/// probing channels 1-30 if SDP fails.
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
    if (_toIsolate != null) {
      _toIsolate!.send({'cmd': 'disconnect'});
      // Give isolate time to close the RFCOMM fd cleanly before killing.
      // Without this, the fd leaks and the radio's RFCOMM channel stays
      // occupied, blocking reconnection.
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

    // Write queue: filled by receivePort listener, drained by read loop.
    // This works because the async read loop yields via Future.delayed,
    // allowing the event loop to process incoming ReceivePort messages.
    final writeQueue = <Uint8List>[];

    // Listen for commands from the main isolate
    receivePort.listen((dynamic message) {
      if (message is! Map<String, dynamic>) return;
      final cmd = message['cmd'] as String?;
      switch (cmd) {
        case 'write':
          if (rfcommFd < 0) return;
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

        // Step 3: Probe channels 1-30 if SDP failed
        if (rfcommFd < 0) {
          _debug(toMain, 'Step 3: Probing RFCOMM channels 1-30...');
          rfcommFd = _probeChannels(bdaddr, toMain);
        }

        if (rfcommFd >= 0) {
          _debug(toMain, 'Connected on fd=$rfcommFd');
          break;
        }

        _debug(toMain, 'Attempt $attempt failed — no GAIA-responsive channel');
        if (attempt < 3 && running) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      } catch (e, st) {
        _debug(toMain, 'Attempt $attempt error: $e\n$st');
        if (rfcommFd >= 0) {
          NativeMethods.close(rfcommFd);
          rfcommFd = -1;
        }
        if (attempt < 3 && running) {
          await Future<void>.delayed(const Duration(seconds: 3));
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

    // Read loop (async — yields to event loop so write queue gets filled)
    await _runReadLoop(rfcommFd, toMain, writeQueue, () => running);

    // Cleanup
    NativeMethods.close(rfcommFd);
    rfcommFd = -1;
    toMain.send(<String, dynamic>{
      'event': 'disconnected',
      'msg': 'Connection closed',
    });
  }

  /// Async read loop that yields to the isolate event loop on idle cycles.
  ///
  /// This is critical: Dart isolates are single-threaded. Using synchronous
  /// `sleep()` would block the event loop, preventing the ReceivePort listener
  /// from processing write commands. By using `await Future.delayed()` instead,
  /// we yield to the event loop which processes queued writes between reads.
  static Future<void> _runReadLoop(
    int fd,
    SendPort toMain,
    List<Uint8List> writeQueue,
    bool Function() isRunning,
  ) async {
    final accumulator = Uint8List(4096);
    var accPtr = 0;
    var accLen = 0;
    final readBufSize = 1024;
    final readBuf = calloc<Uint8>(readBufSize);

    // Block SIGPROF/SIGALRM for read/write syscalls — Dart VM's profiler
    // sends SIGPROF which interrupts RFCOMM syscalls with EINTR.
    // We block before each syscall batch and unblock before yielding,
    // so the VM can still profile during the await.
    final blockSet = calloc<Uint8>(sigsetSize);
    final oldSet = calloc<Uint8>(sigsetSize);
    NativeMethods.sigemptyset(blockSet);
    NativeMethods.sigaddset(blockSet, sigprof);
    NativeMethods.sigaddset(blockSet, sigalrm);

    try {
      while (isRunning()) {
        // Block signals for the syscall batch
        NativeMethods.sigprocmask(sigBlock, blockSet, oldSet);

        // Drain write queue — process pending writes from the main isolate
        while (writeQueue.isNotEmpty) {
          final data = writeQueue.removeAt(0);
          _writeAll(fd, data, signalsAlreadyBlocked: true);
        }

        final bytesRead =
            NativeMethods.read(fd, readBuf.cast<Void>(), readBufSize);

        // Capture errno immediately while signals are still blocked
        final err = bytesRead < 0 ? NativeMethods.errno : 0;

        // Restore signals before any potential yield
        NativeMethods.sigprocmask(sigBlock, oldSet, nullptr.cast<Uint8>());

        if (bytesRead < 0) {
          if (err == eagain || err == eintr) {
            // No data available — yield to event loop (processes writes)
            await Future<void>.delayed(const Duration(milliseconds: 50));
            continue;
          }
          // Real error
          toMain.send(<String, dynamic>{
            'event': 'log',
            'msg': 'Read error: errno=$err',
          });
          break;
        }

        if (bytesRead == 0) {
          // Remote closed connection
          toMain.send(<String, dynamic>{
            'event': 'log',
            'msg': 'Remote closed connection (read returned 0)',
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

        // Ensure we don't overflow the accumulator
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
      calloc.free(blockSet);
      calloc.free(oldSet);
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
      final stdout = (result.stdout as String).trim();
      _debug(toMain, 'bluetoothctl connect: exit=${result.exitCode}, stdout=$stdout');
      // Wait for ACL link to stabilize — radios need time after reconnect
      final delay = stdout.contains('already connected') ? 1 : 3;
      await Future<void>.delayed(Duration(seconds: delay));
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
    for (int ch = 1; ch <= 30; ch++) {
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

  /// Sends GAIA GET_DEV_ID and checks for a valid FF 01 response.
  /// Blocks SIGPROF around all syscalls to prevent EINTR.
  static bool _verifyGaiaResponse(int fd, int channel, SendPort toMain) {
    // Block SIGPROF for the entire verification sequence
    final blockSet = calloc<Uint8>(sigsetSize);
    final oldSet = calloc<Uint8>(sigsetSize);
    NativeMethods.sigemptyset(blockSet);
    NativeMethods.sigaddset(blockSet, sigprof);
    NativeMethods.sigaddset(blockSet, sigalrm);
    NativeMethods.sigprocmask(sigBlock, blockSet, oldSet);

    try {
      return _verifyGaiaResponseInner(fd, channel, toMain);
    } finally {
      // Restore original signal mask
      NativeMethods.sigprocmask(sigBlock, oldSet, nullptr.cast<Uint8>());
      calloc.free(blockSet);
      calloc.free(oldSet);
    }
  }

  static bool _verifyGaiaResponseInner(int fd, int channel, SendPort toMain) {
    // Build GET_DEV_ID: group=BASIC(2), cmd=GET_DEV_ID(1)
    // Command payload: [group_hi=0x00, group_lo=0x02, cmd_hi=0x00, cmd_lo=0x01]
    final gaiaCmd =
        GaiaProtocol.encode(Uint8List.fromList([0x00, 0x02, 0x00, 0x01]));

    // Log the exact bytes we're sending
    final hexStr = gaiaCmd.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    _debug(toMain, 'Ch $channel: sending GAIA GET_DEV_ID: $hexStr (${gaiaCmd.length} bytes)');

    // Write
    final writeBuf = calloc<Uint8>(gaiaCmd.length);
    try {
      for (int i = 0; i < gaiaCmd.length; i++) {
        writeBuf[i] = gaiaCmd[i];
      }
      final sent =
          NativeMethods.write(fd, writeBuf.cast<Void>(), gaiaCmd.length);
      if (sent < 0) {
        _debug(toMain, 'Ch $channel: write failed errno=${NativeMethods.errno}');
        return false;
      }
      _debug(toMain, 'Ch $channel: wrote $sent bytes');
    } finally {
      calloc.free(writeBuf);
    }

    // Poll for response with 5-second timeout
    final pfd = calloc<PollFd>();
    try {
      pfd.ref.fd = fd;
      pfd.ref.events = pollin;
      pfd.ref.revents = 0;

      final pollResult = NativeMethods.poll(pfd, 1, 5000);
      _debug(toMain, 'Ch $channel: poll=$pollResult, revents=0x${pfd.ref.revents.toRadixString(16)}');

      if (pollResult <= 0) {
        if (pollResult < 0) {
          _debug(toMain, 'Ch $channel: poll errno=${NativeMethods.errno}');
        }
        return false;
      }

      if ((pfd.ref.revents & (pollerr | pollhup | pollnval)) != 0) {
        return false;
      }

      if ((pfd.ref.revents & pollin) == 0) return false;
    } finally {
      calloc.free(pfd);
    }

    // Read response
    final readBuf = calloc<Uint8>(1024);
    try {
      final bytesRead =
          NativeMethods.read(fd, readBuf.cast<Void>(), 1024);
      if (bytesRead <= 0) {
        _debug(toMain, 'Ch $channel: read returned $bytesRead, errno=${NativeMethods.errno}');
        return false;
      }

      // Log response bytes
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

      int result;
      int err = 0;
      try {
        result = NativeMethods.connect(fd, addr.cast<Void>(), 10);
        if (result < 0) err = NativeMethods.errno;
      } finally {
        // Restore original signal mask
        NativeMethods.sigprocmask(sigBlock, oldSet, nullptr.cast<Uint8>());
      }

      if (result == 0) {
        _debug(toMain, 'RFCOMM connected: fd=$fd, ch=$channel');
        return fd;
      }

      _debug(toMain, 'connect(ch=$channel) failed: errno=$err');
      NativeMethods.close(fd);
      return -1;
    } finally {
      calloc.free(addr);
      calloc.free(blockSet);
      calloc.free(oldSet);
    }
  }

  static void _writeAll(int fd, Uint8List data,
      {bool signalsAlreadyBlocked = false}) {
    Pointer<Uint8>? blockSet;
    Pointer<Uint8>? oldSet;

    // Block SIGPROF/SIGALRM around write() unless already blocked by caller
    if (!signalsAlreadyBlocked) {
      blockSet = calloc<Uint8>(sigsetSize);
      oldSet = calloc<Uint8>(sigsetSize);
      NativeMethods.sigemptyset(blockSet);
      NativeMethods.sigaddset(blockSet, sigprof);
      NativeMethods.sigaddset(blockSet, sigalrm);
      NativeMethods.sigprocmask(sigBlock, blockSet, oldSet);
    }

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
      if (!signalsAlreadyBlocked && blockSet != null && oldSet != null) {
        NativeMethods.sigprocmask(sigBlock, oldSet, nullptr.cast<Uint8>());
        calloc.free(blockSet);
        calloc.free(oldSet);
      }
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
