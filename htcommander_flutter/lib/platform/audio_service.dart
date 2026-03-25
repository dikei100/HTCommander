import 'dart:typed_data';

/// Abstract audio output for decoded radio audio playback.
abstract class AudioOutput {
  /// Start audio output and subscribe to decoded audio from the radio.
  Future<void> start(int radioDeviceId);

  /// Write 16-bit mono PCM samples for playback.
  void writePcmMono(Uint8List monoSamples);

  /// Stop audio output.
  void stop();
}

/// Abstract microphone capture for radio transmission.
abstract class MicCapture {
  /// Start capturing from the default microphone.
  Future<void> start(int radioDeviceId);

  /// Stop capturing.
  void stop();
}
