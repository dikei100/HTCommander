import 'package:flutter/services.dart';

import '../speech_service.dart';

/// Android TTS service using the platform TextToSpeech API via MethodChannel.
class AndroidSpeechService extends SpeechService {
  static const _channel = MethodChannel('com.htcommander/speech');
  bool _available = false;

  AndroidSpeechService() {
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    try {
      _available =
          await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      _available = false;
    }
  }

  @override
  bool get isAvailable => _available;

  @override
  Future<List<String>> getVoices() async {
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('getVoices');
      return result?.cast<String>() ?? [];
    } on PlatformException {
      return [];
    }
  }

  @override
  void selectVoice(String voiceName) {
    _channel
        .invokeMethod<void>('selectVoice', {'voice': voiceName})
        .catchError((_) {});
  }

  @override
  Future<Uint8List?> synthesizeToWav(String text, int sampleRate) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'synthesizeToWav',
        {'text': text, 'sampleRate': sampleRate},
      );
      return result;
    } on PlatformException {
      return null;
    }
  }
}
