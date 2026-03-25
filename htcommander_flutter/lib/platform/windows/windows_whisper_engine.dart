/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'dart:typed_data';

import '../whisper_engine.dart';

/// Windows Whisper STT engine using whisper.cpp CLI subprocess.
///
/// Accumulates PCM audio during a voice segment, writes a temporary WAV file,
/// and runs whisper-cli.exe for inference. Same subprocess pattern as
/// LinuxWhisperEngine but uses where.exe for binary resolution.
class WindowsWhisperEngine implements WhisperEngine {
  final String _modelPath;
  final String _language;
  String? _binaryPath;
  bool _disposed = false;

  // Audio accumulation buffer (32kHz, 16-bit mono PCM).
  final List<Uint8List> _audioBuffer = [];
  int _totalBytes = 0;
  bool _processing = false;
  String _currentChannel = '';

  // Safety limit: 60 seconds of 32kHz 16-bit mono = 3,840,000 bytes.
  static const int _maxBufferBytes = 32000 * 2 * 60;

  @override
  void Function(String message)? onDebugMessage;
  @override
  void Function(bool processing)? onProcessingVoice;
  @override
  void Function(String text, String channel, DateTime time, bool completed)?
      onTextReady;

  WindowsWhisperEngine(this._modelPath, this._language) {
    _resolveBinary();
  }

  /// Tries to find whisper-cli.exe, whisper.exe, or main.exe on PATH.
  void _resolveBinary() {
    for (final name in ['whisper-cli', 'whisper', 'main']) {
      try {
        final result = Process.runSync('where.exe', [name]);
        if (result.exitCode == 0) {
          // where.exe may return multiple lines; take the first match.
          final path = result.stdout.toString().trim().split('\n').first.trim();
          if (path.isNotEmpty) {
            _binaryPath = path;
            onDebugMessage?.call('Whisper binary found: $_binaryPath');
            return;
          }
        }
      } catch (_) {}
    }
    onDebugMessage?.call(
        'Whisper binary not found (tried whisper-cli, whisper, main)');
  }

  bool get isAvailable => _binaryPath != null && File(_modelPath).existsSync();

  @override
  void startVoiceSegment() {
    _audioBuffer.clear();
    _totalBytes = 0;
  }

  @override
  void processAudioChunk(
      Uint8List data, int offset, int length, String channelName) {
    if (_disposed || _processing) return;
    if (_binaryPath == null) return;

    _currentChannel = channelName;

    // Copy the relevant portion of the data.
    final chunk = Uint8List.sublistView(data, offset, offset + length);
    _audioBuffer.add(chunk);
    _totalBytes += length;

    // Safety: reset if we exceed 60 seconds of audio.
    if (_totalBytes > _maxBufferBytes) {
      onDebugMessage?.call('Audio buffer exceeded 60s limit, resetting');
      resetVoiceSegment();
    }
  }

  @override
  void completeVoiceSegment() {
    if (_disposed || _processing) return;
    if (_audioBuffer.isEmpty || _binaryPath == null) return;

    // Minimum 0.5 seconds of audio (32000 bytes) to avoid spurious inference.
    if (_totalBytes < 32000) {
      startVoiceSegment();
      return;
    }

    _runInference();
  }

  @override
  void resetVoiceSegment() {
    _audioBuffer.clear();
    _totalBytes = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _audioBuffer.clear();
    _totalBytes = 0;
  }

  /// Concatenates buffered audio, writes a temp WAV, runs whisper-cli.
  Future<void> _runInference() async {
    if (_processing) return;
    _processing = true;
    onProcessingVoice?.call(true);

    try {
      // Concatenate all buffered chunks into a single PCM buffer.
      final pcm = Uint8List(_totalBytes);
      int pos = 0;
      for (final chunk in _audioBuffer) {
        pcm.setRange(pos, pos + chunk.length, chunk);
        pos += chunk.length;
      }

      // Write temporary WAV file.
      final tempFile =
          '${Directory.systemTemp.path}\\htcmd_whisper_${DateTime.now().millisecondsSinceEpoch}.wav';
      _writeWav(tempFile, pcm, 32000);

      try {
        // Build whisper-cli arguments.
        final args = <String>[
          '-m', _modelPath,
          '-f', tempFile,
          '--no-timestamps',
          '-np', // no progress output
        ];
        if (_language != 'auto' && _language.isNotEmpty) {
          args.addAll(['-l', _language]);
        }

        onDebugMessage?.call(
            'Running whisper: ${_binaryPath!} ${args.join(" ")}');

        final result = await Process.run(_binaryPath!, args,
            stderrEncoding: const SystemEncoding());

        if (result.exitCode == 0) {
          final output = result.stdout.toString().trim();
          if (output.isNotEmpty) {
            // Whisper outputs each line as a separate utterance.
            // Combine into a single result.
            final text = output
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)
                .join(' ');
            if (text.isNotEmpty) {
              onTextReady?.call(
                  text, _currentChannel, DateTime.now(), true);
            }
          }
        } else {
          onDebugMessage?.call(
              'Whisper exited with code ${result.exitCode}: ${result.stderr}');
        }
      } finally {
        // Clean up temp file.
        try {
          File(tempFile).deleteSync();
        } catch (_) {}
      }
    } catch (e) {
      onDebugMessage?.call('Whisper inference error: $e');
    } finally {
      _processing = false;
      onProcessingVoice?.call(false);

      // Reset buffer for the next segment.
      startVoiceSegment();
    }
  }

  /// Writes a 32kHz 16-bit mono WAV file.
  void _writeWav(String path, Uint8List pcm, int sampleRate) {
    final file = File(path).openSync(mode: FileMode.write);
    try {
      final header = Uint8List(44);
      final bd = ByteData.view(header.buffer);

      // RIFF header
      header[0] = 0x52; // 'R'
      header[1] = 0x49; // 'I'
      header[2] = 0x46; // 'F'
      header[3] = 0x46; // 'F'
      bd.setUint32(4, 36 + pcm.length, Endian.little); // File size - 8
      header[8] = 0x57; // 'W'
      header[9] = 0x41; // 'A'
      header[10] = 0x56; // 'V'
      header[11] = 0x45; // 'E'

      // fmt chunk
      header[12] = 0x66; // 'f'
      header[13] = 0x6D; // 'm'
      header[14] = 0x74; // 't'
      header[15] = 0x20; // ' '
      bd.setUint32(16, 16, Endian.little); // Chunk size
      bd.setUint16(20, 1, Endian.little); // PCM format
      bd.setUint16(22, 1, Endian.little); // Mono
      bd.setUint32(24, sampleRate, Endian.little);
      bd.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
      bd.setUint16(32, 2, Endian.little); // Block align
      bd.setUint16(34, 16, Endian.little); // Bits per sample

      // data chunk
      header[36] = 0x64; // 'd'
      header[37] = 0x61; // 'a'
      header[38] = 0x74; // 't'
      header[39] = 0x61; // 'a'
      bd.setUint32(40, pcm.length, Endian.little);

      file.writeFromSync(header);
      file.writeFromSync(pcm);
    } finally {
      file.closeSync();
    }
  }
}
