import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/data_broker.dart';
import '../../core/data_broker_client.dart';
import '../../radio/audio_resampler.dart';
import '../audio_service.dart';

/// Android audio output using AudioTrack via MethodChannel.
///
/// Subscribes to decoded PCM from RadioAudioManager and pipes it to the
/// Kotlin side for playback through the device speaker.
class AndroidAudioOutput implements AudioOutput {
  static const _channel = MethodChannel('com.htcommander/audio');

  bool _running = false;
  final DataBrokerClient _broker = DataBrokerClient();

  @override
  Future<void> start(int radioDeviceId) async {
    if (_running) return;

    try {
      await _channel.invokeMethod<void>('startPlayback');
      _running = true;

      // Subscribe to decoded audio data from RadioAudioManager
      _broker.subscribe(radioDeviceId, 'AudioDataAvailable',
          (deviceId, name, data) {
        if (data is Uint8List && _running) {
          writePcmMono(data);
        }
      });

      _log('Audio output started (AudioTrack, 32kHz mono)');
    } on PlatformException catch (e) {
      _log('Failed to start audio output: ${e.message}');
      _running = false;
    }
  }

  @override
  void writePcmMono(Uint8List monoSamples) {
    if (!_running) return;
    try {
      _channel.invokeMethod<void>('writePcm', {'data': monoSamples});
    } catch (e) {
      _log('Audio write error: $e');
    }
  }

  @override
  void stop() {
    _running = false;
    _broker.dispose();
    try {
      _channel.invokeMethod<void>('stopPlayback');
    } catch (_) {}
  }

  void _log(String msg) {
    DataBroker.dispatch(1, 'LogInfo', '[AudioOutput]: $msg', store: false);
  }
}

/// Android microphone capture using AudioRecord via MethodChannel/EventChannel.
///
/// Captures at 44100Hz (Android native rate), resamples to 32kHz in Dart,
/// and dispatches TransmitVoicePCM to the radio for SBC encoding.
class AndroidMicCapture implements MicCapture {
  static const _channel = MethodChannel('com.htcommander/audio');
  static const _eventChannel = EventChannel('com.htcommander/mic_events');

  bool _running = false;
  final DataBrokerClient _broker = DataBrokerClient();
  int _radioDeviceId = 0;
  StreamSubscription<dynamic>? _eventSub;

  @override
  Future<void> start(int radioDeviceId) async {
    if (_running) return;
    _radioDeviceId = radioDeviceId;

    try {
      // Subscribe to mic data events from Kotlin
      _eventSub = _eventChannel.receiveBroadcastStream().listen((event) {
        if (!_running || event is! Uint8List) return;

        // Resample 44100Hz -> 32000Hz
        final pcm32k =
            AudioResampler.resample16BitMono(event, 44100, 32000);

        // Dispatch to radio for SBC encoding and transmission
        _broker.dispatch(_radioDeviceId, 'TransmitVoicePCM', pcm32k,
            store: false);
      });

      await _channel.invokeMethod<void>('startCapture');
      _running = true;

      _log('Mic capture started (AudioRecord, 44100Hz -> 32kHz)');
    } on PlatformException catch (e) {
      _log('Failed to start mic capture: ${e.message}');
      _running = false;
    }
  }

  @override
  void stop() {
    _running = false;
    _eventSub?.cancel();
    _eventSub = null;
    try {
      _channel.invokeMethod<void>('stopCapture');
    } catch (_) {}
    _broker.dispose();
  }

  void _log(String msg) {
    DataBroker.dispatch(1, 'LogInfo', '[MicCapture]: $msg', store: false);
  }
}
