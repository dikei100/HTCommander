import 'dart:typed_data';

import '../whisper_engine.dart';

/// Stub whisper engine for Android — STT not yet available.
class AndroidWhisperEngine extends WhisperEngine {
  @override
  void Function(String message)? onDebugMessage;

  @override
  void Function(bool processing)? onProcessingVoice;

  @override
  void Function(String text, String channel, DateTime time, bool completed)?
      onTextReady;

  @override
  void startVoiceSegment() {}

  @override
  void completeVoiceSegment() {}

  @override
  void resetVoiceSegment() {}

  @override
  void processAudioChunk(
      Uint8List data, int offset, int length, String channelName) {}

  @override
  void dispose() {}
}
