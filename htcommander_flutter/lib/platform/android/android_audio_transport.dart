import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/data_broker.dart';
import '../../platform/bluetooth_service.dart';

/// Android audio RFCOMM transport using MethodChannel/EventChannel.
///
/// The radio uses a separate RFCOMM channel (GenericAudio UUID 00001203)
/// for SBC-encoded bidirectional audio. This transport bridges Dart to the
/// Kotlin BluetoothSocket on a background thread.
class AndroidRadioAudioTransport extends RadioAudioTransport {
  static const _methodChannel =
      MethodChannel('com.htcommander/audio_transport');
  static const _eventChannel =
      EventChannel('com.htcommander/audio_transport_events');

  bool _connected = false;
  bool _disposed = false;
  StreamSubscription<dynamic>? _eventSub;

  /// Buffered audio data received from the Kotlin side, consumed by [read].
  final _readBuffer = StreamController<Uint8List>();

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(String macAddress) async {
    if (_disposed) throw StateError('Transport has been disposed');

    // Clean up any existing subscription from a previous connect cycle
    _eventSub?.cancel();

    // Subscribe to incoming audio data events
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (_disposed) return;
        if (event is Uint8List) {
          _readBuffer.add(event);
        } else if (event is Map) {
          final map = Map<String, dynamic>.from(event);
          if (map['event'] == 'disconnected') {
            _connected = false;
            _log('Audio transport disconnected');
          }
        }
      },
      onError: (Object error) {
        _connected = false;
        _log('Audio transport stream error: $error');
      },
      onDone: () {
        _connected = false;
      },
    );

    final mac =
        macAddress.replaceAll(':', '').replaceAll('-', '').toUpperCase();

    try {
      await _methodChannel.invokeMethod<void>('connect', {'mac': mac});
      _connected = true;
    } on PlatformException catch (e) {
      _eventSub?.cancel();
      _eventSub = null;
      throw Exception('Audio transport connect failed: ${e.message}');
    }
  }

  @override
  void disconnect() {
    _connected = false;
    _methodChannel.invokeMethod<void>('disconnect').catchError((_) {});
    _eventSub?.cancel();
    _eventSub = null;
  }

  @override
  Future<Uint8List?> read(int maxBytes) async {
    if (_disposed || !_connected) return null;
    try {
      return await _readBuffer.stream.first;
    } on StateError {
      // Stream was closed
      _connected = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(Uint8List data) async {
    if (_disposed || !_connected) return;
    try {
      await _methodChannel.invokeMethod<void>('write', {'data': data});
    } on PlatformException {
      // Write failed — connection may be lost
    }
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    _readBuffer.close();
  }

  void _log(String msg) {
    DataBroker.dispatch(1, 'LogInfo', '[AudioTransport]: $msg', store: false);
  }
}
