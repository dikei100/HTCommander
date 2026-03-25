/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

/// Platform-agnostic speech-to-text engine interface.
/// Port of HTCommander.Core/Interfaces/IWhisperEngine.cs
abstract class WhisperEngine {
  /// Begins a new voice segment. Resets internal audio buffer.
  void startVoiceSegment();

  /// Signals end of voice segment. Triggers inference on accumulated audio.
  void completeVoiceSegment();

  /// Resets the engine, discarding any buffered audio.
  void resetVoiceSegment();

  /// Feeds a PCM audio chunk to the engine for accumulation.
  /// Audio format: 16-bit signed, 32kHz, mono.
  void processAudioChunk(
      Uint8List data, int offset, int length, String channelName);

  /// Releases resources.
  void dispose();

  /// Called with debug/status messages from the engine.
  void Function(String message)? onDebugMessage;

  /// Called when the engine starts/stops processing voice.
  void Function(bool processing)? onProcessingVoice;

  /// Called when transcribed text is ready.
  /// Parameters: text, channelName, timestamp, completed (true = final result).
  void Function(String text, String channel, DateTime time, bool completed)?
      onTextReady;
}
