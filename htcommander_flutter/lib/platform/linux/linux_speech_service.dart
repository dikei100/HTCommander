/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'dart:typed_data';

import '../speech_service.dart';

/// Linux text-to-speech service using espeak-ng.
/// Port of HTCommander.Platform.Linux/LinuxSpeechService.cs
class LinuxSpeechService extends SpeechService {
  bool _available = false;
  String? _selectedVoice;

  LinuxSpeechService() {
    _checkEspeakAvailable();
  }

  @override
  bool get isAvailable => _available;

  void _checkEspeakAvailable() {
    try {
      final result = Process.runSync('espeak-ng', ['--version']);
      _available = result.exitCode == 0;
    } catch (_) {
      _available = false;
    }
  }

  @override
  Future<List<String>> getVoices() async {
    if (!_available) return [];
    try {
      final result = await Process.run('espeak-ng', ['--voices']);
      if (result.exitCode != 0) return [];
      final lines = (result.stdout as String).split('\n');
      if (lines.isEmpty) return [];
      // Skip header line
      final voices = <String>[];
      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length > 3) {
          voices.add(parts[3]);
        }
      }
      return voices;
    } catch (_) {
      return [];
    }
  }

  @override
  void selectVoice(String voiceName) {
    _selectedVoice = voiceName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-+]'), '');
  }

  @override
  Future<Uint8List?> synthesizeToWav(String text, int sampleRate) async {
    if (!_available) return null;
    final tempFile =
        '${Directory.systemTemp.path}/htcmd_tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      final args = <String>[
        if (_selectedVoice != null) ...['-v', _selectedVoice!],
        '-s',
        '110',
        '-w',
        tempFile,
        text,
      ];
      final result = await Process.run('espeak-ng', args).timeout(
        const Duration(seconds: 10),
      );
      if (result.exitCode != 0) return null;

      final file = File(tempFile);
      if (!await file.exists()) return null;
      var wavBytes = await file.readAsBytes();

      // Extract source sample rate from WAV header bytes 24-27 (little-endian int32)
      if (wavBytes.length < 44) return wavBytes;
      final srcRate = wavBytes[24] |
          (wavBytes[25] << 8) |
          (wavBytes[26] << 16) |
          (wavBytes[27] << 24);

      if (srcRate != sampleRate && srcRate > 0) {
        wavBytes = _resample(wavBytes, srcRate, sampleRate);
      }

      return wavBytes;
    } catch (_) {
      return null;
    } finally {
      try {
        final file = File(tempFile);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Uint8List _resample(Uint8List wav, int srcRate, int dstRate) {
    const headerSize = 44;
    final srcDataSize = wav.length - headerSize;
    final srcSamples = srcDataSize ~/ 2; // 16-bit mono
    final dstSamples = (srcSamples * dstRate / srcRate).round();
    final dstDataSize = dstSamples * 2;

    // Build new WAV with resampled data
    final result = Uint8List(headerSize + dstDataSize);
    // Copy header
    result.setRange(0, headerSize, wav);

    // Update sample rate (bytes 24-27)
    result[24] = dstRate & 0xFF;
    result[25] = (dstRate >> 8) & 0xFF;
    result[26] = (dstRate >> 16) & 0xFF;
    result[27] = (dstRate >> 24) & 0xFF;

    // Update byte rate (bytes 28-31): sampleRate * numChannels * bitsPerSample/8
    final byteRate = dstRate * 2; // mono, 16-bit
    result[28] = byteRate & 0xFF;
    result[29] = (byteRate >> 8) & 0xFF;
    result[30] = (byteRate >> 16) & 0xFF;
    result[31] = (byteRate >> 24) & 0xFF;

    // Update data chunk size (bytes 40-43)
    result[40] = dstDataSize & 0xFF;
    result[41] = (dstDataSize >> 8) & 0xFF;
    result[42] = (dstDataSize >> 16) & 0xFF;
    result[43] = (dstDataSize >> 24) & 0xFF;

    // Update file size (bytes 4-7): total file size - 8
    final fileSize = result.length - 8;
    result[4] = fileSize & 0xFF;
    result[5] = (fileSize >> 8) & 0xFF;
    result[6] = (fileSize >> 16) & 0xFF;
    result[7] = (fileSize >> 24) & 0xFF;

    // Linear interpolation resampling
    final ratio = srcRate / dstRate;
    for (var i = 0; i < dstSamples; i++) {
      final srcPos = i * ratio;
      final srcIndex = srcPos.floor();
      final frac = srcPos - srcIndex;

      final s0 = _getSample(wav, headerSize, srcIndex, srcSamples);
      final s1 = _getSample(wav, headerSize, srcIndex + 1, srcSamples);
      var sample = (s0 + (s1 - s0) * frac).round();

      // Clamp to 16-bit signed range
      if (sample > 32767) sample = 32767;
      if (sample < -32768) sample = -32768;

      // Write 16-bit little-endian
      final offset = headerSize + i * 2;
      result[offset] = sample & 0xFF;
      result[offset + 1] = (sample >> 8) & 0xFF;
    }

    return result;
  }

  int _getSample(Uint8List wav, int headerSize, int index, int totalSamples) {
    if (index < 0) index = 0;
    if (index >= totalSamples) index = totalSamples - 1;
    final offset = headerSize + index * 2;
    if (offset + 1 >= wav.length) return 0;
    final low = wav[offset];
    final high = wav[offset + 1];
    var value = low | (high << 8);
    // Sign-extend 16-bit
    if (value >= 0x8000) value -= 0x10000;
    return value;
  }
}
