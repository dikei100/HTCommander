import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../platform/speech_service.dart';
import '../platform/whisper_engine.dart';
import '../radio/morse_engine.dart';
import '../radio/sstv/sstv_monitor.dart';
import '../radio/wav_file_writer.dart';

/// VoiceHandler — processes Chat, Speak, Morse commands, SSTV monitoring,
/// audio recording, and STT/TTS integration.
///
/// Port of HTCommander.Core/Utils/VoiceHandler.cs
class VoiceHandler {
  final DataBrokerClient _broker = DataBrokerClient();
  bool _disposed = false;
  bool _enabled = false;
  int _targetDeviceId = -1; // -1 means disabled

  /// SSTV monitor instance for decoding SSTV images from audio.
  SstvMonitor? _sstvMonitor;

  /// Decoded text history for the communication screen.
  final List<DecodedTextEntry> _decodedTextHistory = [];
  static const int _maxHistoryEntries = 1000;

  /// Audio recording state.
  bool _recordingEnabled = false;
  WavFileWriter? _currentRecording;
  String? _recordingsPath;
  String? _appDataPath;

  /// Voice text persistence file.
  static const String _voiceTextFileName = 'voicetext.json';

  /// STT/TTS settings.
  String voiceLanguage = 'auto';
  bool speechToTextEnabled = false;
  String _voiceModel = 'base';

  /// Text-to-speech service (set by platform layer via app_init.dart).
  SpeechService? speechService;

  /// Speech-to-text engine (set by platform layer via app_init.dart).
  /// Factory: (modelPath, language) => WhisperEngine
  static WhisperEngine Function(String modelPath, String language)?
      whisperEngineFactory;

  WhisperEngine? _whisperEngine;
  String _currentChannelName = '';
  bool _currentAudioIsTransmit = false;

  List<DecodedTextEntry> get decodedTextHistory =>
      List.unmodifiable(_decodedTextHistory);

  VoiceHandler() {
    // Subscribe to VoiceHandlerEnable/Disable commands on device 1
    _broker.subscribe(1, 'VoiceHandlerEnable', _onVoiceHandlerEnable);
    _broker.subscribe(1, 'VoiceHandlerDisable', _onVoiceHandlerDisable);

    // Subscribe to Chat, Speak, Morse from all devices
    _broker.subscribe(DataBroker.allDevices, 'Chat', _onChat);
    _broker.subscribe(DataBroker.allDevices, 'Speak', _onSpeak);
    _broker.subscribe(DataBroker.allDevices, 'Morse', _onMorse);

    // Subscribe to audio data for SSTV monitoring
    _broker.subscribe(
        DataBroker.allDevices, 'AudioDataAvailable', _onAudioDataAvailable);

    // Subscribe to SSTV send requests
    _broker.subscribe(1, 'SendSstvImage', _onSendSstvImage);

    // Subscribe to decoded text requests
    _broker.subscribe(1, 'RequestDecodedTextHistory', _onRequestHistory);

    // Recording control
    _broker.subscribe(1, 'SetRecordingEnabled', _onSetRecordingEnabled);
    _broker.subscribe(
        DataBroker.allDevices, 'AudioDataStart', _onAudioDataStart);
    _broker.subscribe(
        DataBroker.allDevices, 'AudioDataEnd', _onAudioDataEnd);

    // Voice language/STT settings
    _broker.subscribe(0, 'VoiceLanguage', _onVoiceLanguageChanged);
    _broker.subscribe(0, 'SpeechToTextEnabled', _onSttEnabledChanged);

    // Load persisted settings
    voiceLanguage = DataBroker.getValue<String>(0, 'VoiceLanguage', 'auto');
    speechToTextEnabled =
        DataBroker.getValue<int>(0, 'SpeechToTextEnabled', 0) == 1;

    _broker.logInfo('[VoiceHandler] Voice Handler initialized');
  }

  /// Initializes persistence paths. Call after app data directory is known.
  void initialize(String appDataPath) {
    _appDataPath = appDataPath;
    _recordingsPath = '$appDataPath/Recordings';
    final dir = Directory(_recordingsPath!);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    // Create SSTV images directory
    final sstvDir = Directory('$appDataPath/SSTV');
    if (!sstvDir.existsSync()) sstvDir.createSync(recursive: true);

    // Load voice text history from disk
    _loadHistory();
  }

  /// Handles VoiceHandlerEnable command.
  /// Expected data: Map with 'DeviceId', 'Language', 'Model' keys.
  void _onVoiceHandlerEnable(int deviceId, String name, Object? data) {
    if (_disposed || data == null) return;

    try {
      if (data is Map) {
        final targetDevice = data['DeviceId'] as int?;
        final language = data['Language'] as String?;
        // ignore: unused_local_variable
        final model = data['Model'] as String?;

        if (targetDevice == null || language == null) {
          _broker.logError(
              '[VoiceHandler] Invalid VoiceHandlerEnable data format');
          return;
        }

        // Validate that the radio is connected
        final radioState =
            DataBroker.getValue<String>(targetDevice, 'State', '');
        if (radioState != 'Connected') {
          _broker.logError(
              '[VoiceHandler] Cannot enable for device $targetDevice: '
              'Radio is not connected (state: $radioState)');
          return;
        }

        _enabled = true;
        _targetDeviceId = targetDevice;
        voiceLanguage = language;
        _voiceModel = model ?? 'base';
        _broker.logInfo(
            '[VoiceHandler] Enabled for device $targetDevice, language: $language');

        // Initialize STT engine if enabled
        if (speechToTextEnabled) {
          _initializeSttEngine();
        }
      } else {
        _broker.logError(
            '[VoiceHandler] Invalid VoiceHandlerEnable data format');
      }
    } catch (e) {
      _broker.logError('[VoiceHandler] Error in OnVoiceHandlerEnable: $e');
    }
  }

  /// Handles VoiceHandlerDisable command.
  void _onVoiceHandlerDisable(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _cleanupSttEngine();
    _enabled = false;
    _targetDeviceId = -1;
    _broker.logInfo('[VoiceHandler] Disabled');
  }

  /// Handles Chat command — dispatches message to DecodedText on device 1.
  /// In the full implementation, this sends a BSS packet via the radio.
  /// For now, it dispatches the message text to DecodedText for display.
  void _onChat(int deviceId, String name, Object? data) {
    if (_disposed || data == null) return;

    final message = data is String ? data : null;
    if (message == null || message.isEmpty) return;

    // Validate message length (must be > 0 and < 255 characters)
    if (message.length >= 255) {
      _broker.logError(
          '[VoiceHandler] Cannot send chat: Message length must be between '
          '1 and 254 characters (got ${message.length})');
      return;
    }

    // Determine the target device for transmission
    final transmitDeviceId = _resolveTransmitDevice(deviceId);
    if (transmitDeviceId == null) {
      _broker.logError(
          '[VoiceHandler] Cannot send chat: No radio is voice-enabled');
      return;
    }

    try {
      final callsign =
          _broker.getValue<String>(0, 'CallSign', '');
      if (callsign.isEmpty) {
        _broker.logError(
            '[VoiceHandler] Cannot send chat: Callsign not configured');
        return;
      }

      _broker.logInfo(
          '[VoiceHandler] Sending chat on device $transmitDeviceId: '
          '$callsign: $message');

      // Dispatch to DecodedText for display in the Communication tab
      final displayText = '$callsign: $message';
      _broker.dispatch(1, 'DecodedText', displayText, store: false);
      _addToHistory(displayText, source: callsign, incoming: false);
    } catch (e) {
      _broker.logError('[VoiceHandler] Error sending chat: $e');
    }
  }

  /// Handles Speak command — synthesizes text to speech via platform TTS
  /// and dispatches PCM audio for radio transmission.
  void _onSpeak(int deviceId, String name, Object? data) {
    if (_disposed || data == null) return;

    final textToSpeak = data is String ? data : null;
    if (textToSpeak == null || textToSpeak.isEmpty) return;

    final transmitDeviceId = _resolveTransmitDevice(deviceId);
    if (transmitDeviceId == null) {
      _broker.logError(
          '[VoiceHandler] Cannot speak: No radio is voice-enabled');
      return;
    }

    if (speechService == null || !speechService!.isAvailable) {
      _broker.logError(
          '[VoiceHandler] Cannot speak: Text-to-Speech not available');
      return;
    }

    // Run TTS asynchronously
    _synthesizeAndTransmit(textToSpeak, transmitDeviceId);
  }

  /// Synthesizes text to WAV and dispatches PCM for transmission.
  Future<void> _synthesizeAndTransmit(
      String text, int transmitDeviceId) async {
    try {
      final wavData = await speechService!.synthesizeToWav(text, 32000);
      if (wavData == null || wavData.length <= 44) {
        _broker.logError('[VoiceHandler] TTS synthesis returned no audio');
        return;
      }

      // Extract raw PCM from WAV (skip 44-byte header)
      final pcm = Uint8List.sublistView(wavData, 44);
      _broker.logInfo(
          '[VoiceHandler] TTS synthesized ${pcm.length} bytes of PCM');

      // Dispatch for radio transmission
      _broker.dispatch(transmitDeviceId, 'TransmitVoicePCM', pcm,
          store: false);
    } catch (e) {
      _broker.logError('[VoiceHandler] TTS synthesis error: $e');
    }
  }

  /// Handles Morse command — generates morse PCM and dispatches TransmitVoicePCM.
  void _onMorse(int deviceId, String name, Object? data) {
    if (_disposed || data == null) return;

    final textToMorse = data is String ? data : null;
    if (textToMorse == null || textToMorse.isEmpty) return;

    final transmitDeviceId = _resolveTransmitDevice(deviceId);
    if (transmitDeviceId == null) {
      _broker.logError(
          '[VoiceHandler] Cannot transmit morse: No radio is voice-enabled');
      return;
    }

    try {
      _broker.logInfo(
          '[VoiceHandler] Generating morse code on device $transmitDeviceId: '
          '$textToMorse');

      // Generate morse code PCM (8-bit unsigned, 32kHz)
      final morsePcm8bit = MorseEngine.generateMorsePcm(textToMorse);

      if (morsePcm8bit.isEmpty) {
        _broker.logError('[VoiceHandler] Failed to generate morse code PCM');
        return;
      }

      // Convert 8-bit unsigned PCM to 16-bit signed PCM
      // 8-bit unsigned: 0-255, with 128 as center (silence)
      // 16-bit signed: -32768 to 32767, with 0 as center (silence)
      final pcmData = Uint8List(morsePcm8bit.length * 2);
      for (int i = 0; i < morsePcm8bit.length; i++) {
        final int sample16 = ((morsePcm8bit[i] - 128) * 256);
        pcmData[i * 2] = sample16 & 0xFF;
        pcmData[i * 2 + 1] = (sample16 >> 8) & 0xFF;
      }

      // Send PCM data to the radio for transmission via DataBroker
      // Include PlayLocally=true so the user can hear the morse output
      _broker.dispatch(
          transmitDeviceId,
          'TransmitVoicePCM',
          <String, Object>{'Data': pcmData, 'PlayLocally': true},
          store: false);
      _broker.logInfo(
          '[VoiceHandler] Transmitted ${pcmData.length} bytes of morse PCM '
          'to device $transmitDeviceId');
    } catch (e) {
      _broker.logError('[VoiceHandler] Error generating morse code: $e');
    }
  }

  /// Whether the voice handler is currently enabled.
  bool get isEnabled => _enabled;

  // ── SSTV Monitoring ──

  void _onAudioDataAvailable(int deviceId, String name, Object? data) {
    if (_disposed || !_enabled) return;
    if (data is! Map) return;

    final pcmData = data['Data'];
    if (pcmData is! Uint8List) return;

    // Track channel name and TX/RX state for STT attribution
    _currentChannelName = (data['ChannelName'] as String?) ?? '';
    _currentAudioIsTransmit = data['Transmit'] == true;

    // Initialize SSTV monitor on first audio
    _sstvMonitor ??= _createSstvMonitor();

    // Feed audio samples to the SSTV decoder
    // Convert 16-bit PCM bytes to double samples
    final sampleCount = pcmData.length ~/ 2;
    final samples = Float64List(sampleCount);
    final bd = ByteData.view(pcmData.buffer, pcmData.offsetInBytes);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }

    _sstvMonitor!.processFloatSamples(samples);

    // Feed audio to Whisper STT engine
    if (_whisperEngine != null) {
      final length = (data['Length'] as int?) ?? pcmData.length;
      _whisperEngine!.processAudioChunk(pcmData, 0, length, _currentChannelName);
    }

    // Write to recording if active
    final recording = _currentRecording;
    if (recording != null) {
      recording.writeSamples(pcmData);
    }
  }

  SstvMonitor _createSstvMonitor() {
    final monitor = SstvMonitor(sampleRate: 32000);
    monitor.onDecodingStarted = (event) {
      _broker.logInfo(
          '[VoiceHandler] SSTV decoding started: ${event.modeName} '
          '(${event.width}x${event.height})');
      _broker.dispatch(1, 'SstvDecodingStarted', event, store: false);
    };
    monitor.onDecodingProgress = (event) {
      _broker.dispatch(1, 'SstvDecodingProgress', event, store: false);
    };
    monitor.onDecodingComplete = (event) {
      _broker.logInfo(
          '[VoiceHandler] SSTV decoding complete: ${event.modeName}');
      _broker.dispatch(1, 'SstvDecodingComplete', event, store: false);
      if (event.pixels != null) {
        _broker.dispatch(1, 'SstvImage', event, store: false);
      }
    };
    return monitor;
  }

  void _onSendSstvImage(int deviceId, String name, Object? data) {
    if (_disposed) return;
    // The actual encoding and transmission is handled by CommunicationScreen
    // which calls the SstvEncoder directly and dispatches TransmitVoicePCM.
    // This handler just logs the event.
    _broker.logInfo('[VoiceHandler] SSTV image send requested');
  }

  // ── Decoded Text History ──

  void _addToHistory(String text, {String source = '', bool incoming = true}) {
    final entry = DecodedTextEntry(
      time: DateTime.now(),
      text: text,
      source: source,
      incoming: incoming,
    );
    _decodedTextHistory.add(entry);
    while (_decodedTextHistory.length > _maxHistoryEntries) {
      _decodedTextHistory.removeAt(0);
    }
    _broker.dispatch(1, 'DecodedTextHistoryUpdated',
        _decodedTextHistory.length, store: false);

    // Persist every 10 entries
    if (_decodedTextHistory.length % 10 == 0) {
      _saveHistory();
    }
  }

  void _onRequestHistory(int deviceId, String name, Object? data) {
    _broker.dispatch(1, 'DecodedTextHistory',
        List<DecodedTextEntry>.from(_decodedTextHistory), store: false);
  }

  // ── Audio Recording ──

  void _onSetRecordingEnabled(int deviceId, String name, Object? data) {
    if (data is bool) {
      _recordingEnabled = data;
      _broker.logInfo(
          '[VoiceHandler] Recording ${_recordingEnabled ? "enabled" : "disabled"}');
    }
  }

  void _onAudioDataStart(int deviceId, String name, Object? data) {
    if (_disposed || !_recordingEnabled) return;
    if (_recordingsPath == null) return;

    final channelName = data is Map ? (data['ChannelName'] ?? '') as String : '';
    _startRecording(channelName);
  }

  void _onAudioDataEnd(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _whisperEngine?.completeVoiceSegment();
    _stopRecording();
  }

  void _startRecording(String channelName) {
    _stopRecording(); // Close any existing recording

    final now = DateTime.now();
    final timestamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final filename = 'recording_$timestamp.wav';
    final path = '$_recordingsPath/$filename';

    try {
      _currentRecording = WavFileWriter(path, sampleRate: 32000);
      _currentRecording!.open();
      _broker.logInfo('[VoiceHandler] Started recording: $filename');
    } catch (e) {
      _broker.logError('[VoiceHandler] Failed to start recording: $e');
      _currentRecording = null;
    }
  }

  void _stopRecording() {
    final recording = _currentRecording;
    if (recording == null) return;

    try {
      recording.close();
      final duration = recording.durationSeconds;
      _broker.logInfo(
          '[VoiceHandler] Stopped recording: ${duration.toStringAsFixed(1)}s');

      // If the recording is too short (<0.5s), delete it
      if (duration < 0.5) {
        try {
          File(recording.path).deleteSync();
        } catch (_) {}
      }
    } catch (e) {
      _broker.logError('[VoiceHandler] Error stopping recording: $e');
    }

    _currentRecording = null;
  }

  // ── Voice Settings ──

  void _onVoiceLanguageChanged(int deviceId, String name, Object? data) {
    if (data is String) voiceLanguage = data;
  }

  void _onSttEnabledChanged(int deviceId, String name, Object? data) {
    final wasEnabled = speechToTextEnabled;
    if (data is int) speechToTextEnabled = data == 1;

    if (speechToTextEnabled && !wasEnabled && _enabled) {
      _initializeSttEngine();
    } else if (!speechToTextEnabled && wasEnabled) {
      _cleanupSttEngine();
    }
  }

  // ── History Persistence ──

  void _loadHistory() {
    final path = _appDataPath;
    if (path == null) return;

    final file = File('$path/$_voiceTextFileName');
    if (!file.existsSync()) return;

    try {
      final json = file.readAsStringSync();
      final list = jsonDecode(json);
      if (list is List) {
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _decodedTextHistory.add(DecodedTextEntry(
              time: DateTime.tryParse(item['time'] ?? '') ?? DateTime.now(),
              text: item['text'] ?? '',
              source: item['source'] ?? '',
              incoming: item['incoming'] ?? true,
            ));
          }
        }
      }
    } catch (e) {
      _broker.logError('[VoiceHandler] Error loading voice text history: $e');
    }
  }

  void _saveHistory() {
    final path = _appDataPath;
    if (path == null) return;

    try {
      final list = _decodedTextHistory
          .map((e) => {
                'time': e.time.toIso8601String(),
                'text': e.text,
                'source': e.source,
                'incoming': e.incoming,
              })
          .toList();
      File('$path/$_voiceTextFileName').writeAsStringSync(jsonEncode(list));
    } catch (e) {
      _broker.logError('[VoiceHandler] Error saving voice text history: $e');
    }
  }

  /// Resolves the target device ID for transmission.
  /// Returns null if no valid target is available.
  int? _resolveTransmitDevice(int deviceId) {
    if (deviceId == 1) {
      // Device 1: use the currently voice-enabled radio
      if (!_enabled || _targetDeviceId <= 0) return null;
      return _targetDeviceId;
    } else if (deviceId >= 100) {
      // Device 100+: use that device ID directly
      return deviceId;
    }
    // Other device IDs (2-99): ignore
    return null;
  }

  // ── Speech-to-Text Engine ──

  void _initializeSttEngine() {
    _cleanupSttEngine();

    if (whisperEngineFactory == null) {
      _broker.logError(
          '[VoiceHandler] WhisperEngineFactory not set — '
          'speech-to-text not available on this platform');
      return;
    }

    final modelName = _voiceModel.toLowerCase();
    final modelPath = '$_appDataPath/ggml-$modelName.bin';
    if (_appDataPath == null || !File(modelPath).existsSync()) {
      _broker.logError(
          '[VoiceHandler] Whisper model file not found: $modelPath');
      return;
    }

    _whisperEngine = whisperEngineFactory!(modelPath, voiceLanguage);
    _whisperEngine!.onDebugMessage = _onWhisperDebug;
    _whisperEngine!.onProcessingVoice = _onWhisperProcessing;
    _whisperEngine!.onTextReady = _onWhisperTextReady;
    _whisperEngine!.startVoiceSegment();

    _broker.logInfo(
        '[VoiceHandler] Whisper STT initialized (model: $modelName, '
        'language: $voiceLanguage)');
  }

  void _cleanupSttEngine() {
    if (_whisperEngine != null) {
      _whisperEngine!.resetVoiceSegment();
      _whisperEngine!.onDebugMessage = null;
      _whisperEngine!.onProcessingVoice = null;
      _whisperEngine!.onTextReady = null;
      _whisperEngine!.dispose();
      _whisperEngine = null;
    }
  }

  void _onWhisperDebug(String msg) {
    _broker.logInfo('[VoiceHandler/Whisper] $msg');
  }

  void _onWhisperProcessing(bool processing) {
    if (_targetDeviceId > 0) {
      _broker.dispatch(_targetDeviceId, 'ProcessingVoice',
          {'Listening': _whisperEngine != null, 'Processing': processing},
          store: false);
    }
  }

  void _onWhisperTextReady(
      String text, String channel, DateTime time, bool completed) {
    if (text.trim().isEmpty) return;
    final isReceived = !_currentAudioIsTransmit;

    _addToHistory(text.trim(), source: channel, incoming: isReceived);
    _broker.dispatch(1, 'DecodedText', text.trim(), store: false);

    if (_targetDeviceId > 0) {
      _broker.dispatch(_targetDeviceId, 'TextReady', {
        'Text': text.trim(),
        'Channel': channel,
        'Time': time.toIso8601String(),
        'Completed': completed,
        'IsReceived': isReceived,
      }, store: false);
    }
  }

  /// Disposes the voice handler and unsubscribes from all events.
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _enabled = false;
      _targetDeviceId = -1;
      _cleanupSttEngine();
      _stopRecording();
      _saveHistory();
      _sstvMonitor = null;
      _broker.dispose();
    }
  }
}

/// A decoded text entry for voice/chat/SSTV history.
class DecodedTextEntry {
  final DateTime time;
  final String text;
  final String source;
  final bool incoming;

  const DecodedTextEntry({
    required this.time,
    required this.text,
    this.source = '',
    this.incoming = true,
  });
}
