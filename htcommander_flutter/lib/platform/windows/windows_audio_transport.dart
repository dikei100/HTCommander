import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../platform/bluetooth_service.dart';
import 'windows_native_methods.dart';

/// Windows audio transport for the radio's audio RFCOMM channel.
///
/// Uses Winsock2 RFCOMM sockets via dart:ffi. The audio channel carries raw
/// SBC data with 0x7E framing — no GAIA protocol. The caller handles all
/// audio frame encoding/decoding.
///
/// Read and write operations run in isolates to avoid blocking the main thread.
class WindowsRadioAudioTransport extends RadioAudioTransport {
  int _sock = invalidSocket;
  bool _connected = false;
  bool _disposed = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(String macAddress) async {
    if (_disposed) throw StateError('Transport has been disposed');

    final wsaResult = initializeWinsock();
    if (wsaResult != 0) {
      throw Exception('WSAStartup failed with error: $wsaResult');
    }

    final mac =
        macAddress.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    final macColon = _formatMacColon(mac);

    // Wait for command channel to stabilize
    await Future<void>.delayed(const Duration(seconds: 2));

    // Probe channels 1-30 for the audio channel.
    // The audio channel is typically a different RFCOMM channel than the
    // GAIA command channel. We try each channel — a successful connect()
    // to a non-GAIA channel is the audio channel.
    for (int ch = 1; ch <= 30; ch++) {
      final sock = _createRfcommSocket(macColon, ch);
      if (sock != invalidSocket) {
        _sock = sock;
        break;
      }
    }

    // Retry with more delay if first attempt failed
    if (_sock == invalidSocket) {
      await Future<void>.delayed(const Duration(seconds: 3));
      for (int ch = 1; ch <= 30; ch++) {
        final sock = _createRfcommSocket(macColon, ch);
        if (sock != invalidSocket) {
          _sock = sock;
          break;
        }
      }
    }

    if (_sock == invalidSocket) {
      throw Exception('Failed to connect to audio channel');
    }

    // Set non-blocking mode via ioctlsocket(FIONBIO)
    final mode = calloc<ffi.Uint32>();
    mode.value = 1;
    final result =
        WindowsNativeMethods.ioctlsocket(_sock, fionbio, mode);
    calloc.free(mode);

    if (result == socketError) {
      final err = WindowsNativeMethods.wsaGetLastError();
      WindowsNativeMethods.closesocket(_sock);
      _sock = invalidSocket;
      throw Exception(
          'Failed to set non-blocking mode on audio socket: WSA=$err');
    }

    _connected = true;
  }

  @override
  Future<Uint8List?> read(int maxBytes) async {
    if (!_connected || _sock == invalidSocket) return null;

    // Run the blocking read in a separate isolate to avoid blocking the main thread
    final sock = _sock;
    return Isolate.run(() => _isolateRead(sock, maxBytes));
  }

  @override
  Future<void> write(Uint8List data) async {
    if (!_connected || _sock == invalidSocket) return;

    final sock = _sock;
    final result = await Isolate.run(() => _isolateWrite(sock, data));
    if (!result) {
      _connected = false;
    }
  }

  @override
  void disconnect() {
    _connected = false;
    if (_sock != invalidSocket) {
      WindowsNativeMethods.closesocket(_sock);
      _sock = invalidSocket;
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

  /// Reads from the Winsock RFCOMM socket. Called inside an isolate.
  static Uint8List? _isolateRead(int sock, int maxBytes) {
    // Open ws2_32.dll fresh in this isolate (DynamicLibrary handles don't
    // cross isolate boundaries)
    final ws2 = ffi.DynamicLibrary.open('ws2_32.dll');
    final recvFn = ws2.lookupFunction<_RecvNative, _RecvDart>('recv');
    final wsaErrorFn = ws2.lookupFunction<_WSAGetLastErrorNative,
        _WSAGetLastErrorDart>('WSAGetLastError');

    final bufSize = maxBytes > 4096 ? 4096 : maxBytes;
    final buf = calloc<ffi.Uint8>(bufSize);
    try {
      // Non-blocking read with retry
      for (int attempts = 0; attempts < 100; attempts++) {
        final bytesRead = recvFn(sock, buf, bufSize, 0);
        if (bytesRead > 0) {
          final result = Uint8List(bytesRead);
          for (int i = 0; i < bytesRead; i++) {
            result[i] = buf[i];
          }
          return result;
        }
        if (bytesRead == 0) return null; // Connection closed
        final err = wsaErrorFn();
        if (err == wsaeWouldBlock || err == wsaeInProgress) {
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

  /// Writes to the Winsock RFCOMM socket. Called inside an isolate.
  /// Returns false on error.
  static bool _isolateWrite(int sock, Uint8List data) {
    final ws2 = ffi.DynamicLibrary.open('ws2_32.dll');
    final sendFn = ws2.lookupFunction<_SendNative, _SendDart>('send');
    final wsaErrorFn = ws2.lookupFunction<_WSAGetLastErrorNative,
        _WSAGetLastErrorDart>('WSAGetLastError');

    final buf = calloc<ffi.Uint8>(data.length);
    try {
      for (int i = 0; i < data.length; i++) {
        buf[i] = data[i];
      }

      var totalWritten = 0;
      while (totalWritten < data.length) {
        final written = sendFn(
          sock,
          buf + totalWritten,
          data.length - totalWritten,
          0,
        );
        if (written > 0) {
          totalWritten += written;
        } else if (written == socketError) {
          final err = wsaErrorFn();
          if (err == wsaeWouldBlock || err == wsaeInProgress) {
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

  static int _createRfcommSocket(String macAddress, int channel) {
    final sock =
        WindowsNativeMethods.socket(afBth, sockStream, bthprotoRfcomm);
    if (sock == invalidSocket) return invalidSocket;

    final addr = buildSockaddrBth(macAddress, channel);
    try {
      final result = WindowsNativeMethods.connect(
          sock, addr.cast<ffi.Void>(), sockaddrBthSize);
      if (result == socketError) {
        WindowsNativeMethods.closesocket(sock);
        return invalidSocket;
      }
    } finally {
      calloc.free(addr);
    }

    return sock;
  }

  static String _formatMacColon(String mac) {
    final parts = <String>[];
    for (int i = 0; i < 6; i++) {
      parts.add(mac.substring(i * 2, i * 2 + 2));
    }
    return parts.join(':');
  }
}

// --- FFI typedefs for isolate-local Winsock lookups ---

typedef _RecvNative = ffi.Int32 Function(
    ffi.IntPtr s, ffi.Pointer<ffi.Uint8> buf, ffi.Int32 len, ffi.Int32 flags);
typedef _RecvDart = int Function(
    int s, ffi.Pointer<ffi.Uint8> buf, int len, int flags);

typedef _SendNative = ffi.Int32 Function(
    ffi.IntPtr s, ffi.Pointer<ffi.Uint8> buf, ffi.Int32 len, ffi.Int32 flags);
typedef _SendDart = int Function(
    int s, ffi.Pointer<ffi.Uint8> buf, int len, int flags);

typedef _WSAGetLastErrorNative = ffi.Int32 Function();
typedef _WSAGetLastErrorDart = int Function();
