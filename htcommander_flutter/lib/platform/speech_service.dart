/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

/// Platform-agnostic text-to-speech service.
/// Windows: System.Speech, Linux: espeak-ng, Android: Android.Speech.Tts.
/// Port of HTCommander.Core/Interfaces/ISpeechService.cs
abstract class SpeechService {
  bool get isAvailable;
  Future<List<String>> getVoices();
  void selectVoice(String voiceName);
  Future<Uint8List?> synthesizeToWav(String text, int sampleRate);
}
