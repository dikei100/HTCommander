import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../platform/bluetooth_service.dart';
import 'native_methods.dart';

/// Generic Audio UUID used by the radios for the audio RFCOMM channel.
const String _genericAudioUuid = '00001203-0000-1000-8000-00805f9b34fb';

/// Linux audio transport for the radio's audio RFCOMM channel.
///
/// Uses native RFCOMM sockets via dart:ffi. The audio channel carries raw
/// SBC data with 0x7E framing — no GAIA protocol.
///
/// Read and write operations run in isolates to avoid blocking the main thread.
class LinuxRadioAudioTransport extends RadioAudioTransport {
  int _rfcommFd = -1;
  bool _connected = false;
  bool _disposed = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(String macAddress) async {
    if (_disposed) throw StateError('Transport has been disposed');

    final mac =
        macAddress.replaceAll(':','').replaceAll('-', '').toUpperCase();
    final macColon = _formatMacColon(mac);
    final bdaddr = parseMacAddress(mac);

    // Wait for command channel to stabilize
    await Future<void>.delayed(const Duration(seconds: 2));

    // Step 1: Discover audio channel via SDP
    final audioChannels = await _discoverAudioChannels(macColon);

    if (audioChannels != null && audioChannels.isNotEmpty) {
      for (final ch in audioChannels) {
        final fd = _createRfcommFd(bdaddr, ch);
        if (fd >= 0) {
          _rfcommFd = fd;
          break;
        }
      }
    }

    // Step 2: Probe channels 1-30
    if (_rfcommFd < 0) {
      for (int ch = 1; ch <= 30; ch++) {
        final fd = _createRfcommFd(bdaddr, ch);
        if (fd >= 0) {
          _rfcommFd = fd;
          break;
        }
      }
    }

    // Step 3: Retry with more delay
    if (_rfcommFd < 0) {
      await Future<void>.delayed(const Duration(seconds: 3));
      for (int ch = 1; ch <= 30; ch++) {
        final fd = _createRfcommFd(bdaddr, ch);
        if (fd >= 0) {
          _rfcommFd = fd;
          break;
        }
      }
    }

    if (_rfcommFd < 0) {
      throw Exception('Failed to connect to audio channel');
    }

    // Set non-blocking mode
    final flags = NativeMethods.fcntl(_rfcommFd, fGetfl);
    if (flags < 0) {
      NativeMethods.close(_rfcommFd);
      _rfcommFd = -1;
      throw Exception('Failed to get socket flags on audio fd');
    }
    NativeMethods.fcntl3(_rfcommFd, fSetfl, flags | oNonblock);

    _connected = true;
  }

  @override
  Future<Uint8List?> read(int maxBytes) async {
    if (!_connected || _rfcommFd < 0) return null;

    // Run the blocking read in a separate isolate to avoid blocking the main thread
    final fd = _rfcommFd;
    return Isolate.run(() => _isolateRead(fd, maxBytes));
  }

  @override
  Future<void> write(Uint8List data) async {
    if (!_connected || _rfcommFd < 0) return;

    final fd = _rfcommFd;
    final result = await Isolate.run(() => _isolateWrite(fd, data));
    if (!result) {
      _connected = false;
    }
  }

  @override
  void disconnect() {
    _connected = false;
    if (_rfcommFd >= 0) {
      NativeMethods.close(_rfcommFd);
      _rfcommFd = -1;
    }
  }

  @override
  void dispose() {
    if (!_disposed) {
      disconnect();
      _disposed = true;
    }
  }

  // --- Static methods for isolate execution ---

  /// Reads from the RFCOMM socket. Called inside an isolate.
  static Uint8List? _isolateRead(int fd, int maxBytes) {
    // Open libc fresh in this isolate (DynamicLibrary handles don't cross isolates)
    final libc = DynamicLibrary.open('libc.so.6');
    final readFn =
        libc.lookupFunction<_ReadNative, _ReadDart>('read');
    final errnoLocFn = libc
        .lookupFunction<_ErrnoLocNative, _ErrnoLocDart>('__errno_location');

    final bufSize = maxBytes > 4096 ? 4096 : maxBytes;
    final buf = calloc<Uint8>(bufSize);
    try {
      // Non-blocking read with retry
      for (int attempts = 0; attempts < 100; attempts++) {
        final bytesRead = readFn(fd, buf.cast<Void>(), bufSize);
        if (bytesRead > 0) {
          final result = Uint8List(bytesRead);
          for (int i = 0; i < bytesRead; i++) {
            result[i] = buf[i];
          }
          return result;
        }
        if (bytesRead == 0) return null; // Connection closed
        final err = errnoLocFn().value;
        if (err == eagain || err == eintr) {
          sleep(const Duration(milliseconds: 10));
          continue;
        }
        return null; // Real error
      }
      return null; // Timed out
    } finally {
      calloc.free(buf);
    }
  }

  /// Writes to the RFCOMM socket. Called inside an isolate. Returns false on error.
  static bool _isolateWrite(int fd, Uint8List data) {
    final libc = DynamicLibrary.open('libc.so.6');
    final writeFn =
        libc.lookupFunction<_WriteNative, _WriteDart>('write');
    final errnoLocFn = libc
        .lookupFunction<_ErrnoLocNative, _ErrnoLocDart>('__errno_location');

    final buf = calloc<Uint8>(data.length);
    try {
      for (int i = 0; i < data.length; i++) {
        buf[i] = data[i];
      }

      var totalWritten = 0;
      while (totalWritten < data.length) {
        final written = writeFn(
          fd,
          (buf.cast<Uint8>() + totalWritten).cast<Void>(),
          data.length - totalWritten,
        );
        if (written > 0) {
          totalWritten += written;
        } else if (written < 0) {
          final err = errnoLocFn().value;
          if (err == eagain || err == eintr) {
            sleep(const Duration(milliseconds: 5));
            continue;
          }
          return false;
        } else {
          return false; // written == 0, unexpected
        }
      }
      return true;
    } finally {
      calloc.free(buf);
    }
  }

  // --- Connection helpers ---

  static Future<List<int>?> _discoverAudioChannels(String macColon) async {
    try {
      final result = await Process.run('sdptool', ['browse', macColon]);
      if (result.exitCode != 0) return null;

      final output = result.stdout as String;
      if (output.isEmpty) return null;

      final audioChannels = <int>[];
      final records = output.split('Service Name:');
      final channelRegex = RegExp(r'Channel:\s*(\d+)');

      for (final record in records) {
        final match = channelRegex.firstMatch(record);
        if (match == null) continue;

        final channel = int.tryParse(match.group(1)!);
        if (channel == null || channel < 1 || channel > 30) continue;

        final isAudio = record.contains(_genericAudioUuid) ||
            record.contains('BS AOC') ||
            record.contains('GenericAudio') ||
            record.contains('00001203');

        if (isAudio) {
          audioChannels.add(channel);
        }
      }

      return audioChannels.isNotEmpty ? audioChannels : null;
    } catch (_) {
      return null;
    }
  }

  static int _createRfcommFd(List<int> bdaddr, int channel) {
    if (bdaddr.length < 6) return -1;

    final fd =
        NativeMethods.socket(afBluetooth, sockStream, btprotoRfcomm);
    if (fd < 0) return -1;

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
      try {
        result = NativeMethods.connect(fd, addr.cast<Void>(), 10);
      } finally {
        // Restore original signal mask
        NativeMethods.sigprocmask(sigBlock, oldSet, nullptr.cast<Uint8>());
      }

      if (result < 0) {
        NativeMethods.close(fd);
        return -1;
      }
    } finally {
      calloc.free(addr);
      calloc.free(blockSet);
      calloc.free(oldSet);
    }

    return fd;
  }

  static String _formatMacColon(String mac) {
    final parts = <String>[];
    for (int i = 0; i < 6; i++) {
      parts.add(mac.substring(i * 2, i * 2 + 2));
    }
    return parts.join(':');
  }
}

// --- FFI typedefs for isolate-local libc lookups ---

typedef _ReadNative = Int64 Function(Int32 fd, Pointer<Void> buf, Int64 count);
typedef _ReadDart = int Function(int fd, Pointer<Void> buf, int count);

typedef _WriteNative = Int64 Function(
    Int32 fd, Pointer<Void> buf, Int64 count);
typedef _WriteDart = int Function(int fd, Pointer<Void> buf, int count);

typedef _ErrnoLocNative = Pointer<Int32> Function();
typedef _ErrnoLocDart = Pointer<Int32> Function();
