import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../../core/data_broker.dart';
import '../../core/data_broker_client.dart';
import '../../radio/audio_resampler.dart';
import '../audio_service.dart';

/// Linux audio output — pipes decoded PCM to paplay subprocess.
///
/// PortAudio opened as stereo on Linux, so mono samples are duplicated
/// to both channels (matching C# LinuxAudioOutput pattern).
class LinuxAudioOutput implements AudioOutput {
  Process? _paplay;
  IOSink? _stdin;
  bool _running = false;
  final DataBrokerClient _broker = DataBrokerClient();
  /// Start audio output and subscribe to decoded audio from the radio.
  Future<void> start(int radioDeviceId) async {
    if (_running) return;

    try {
      _paplay = await Process.start('paplay', [
        '--format=s16le',
        '--rate=32000',
        '--channels=2',
        '--raw',
        '--latency-msec=50',
        '--stream-name=HTCommander Radio Audio',
      ]);
      _stdin = _paplay!.stdin;
      _running = true;

      // Subscribe to decoded audio data from RadioAudioManager
      _broker.subscribe(radioDeviceId, 'AudioDataAvailable',
          (deviceId, name, data) {
        if (data is Uint8List && _running) {
          writePcmMono(data);
        }
      });

      _log('Audio output started (paplay, 32kHz stereo)');
    } catch (e) {
      _log('Failed to start audio output: $e');
      _running = false;
    }
  }

  /// Write 16-bit mono PCM samples — duplicates to stereo for Linux.
  void writePcmMono(Uint8List monoSamples) {
    if (!_running || _stdin == null) return;
    try {
      // Duplicate mono to stereo (2 bytes per sample → 4 bytes per frame)
      final stereo = Uint8List(monoSamples.length * 2);
      for (var i = 0; i < monoSamples.length; i += 2) {
        if (i + 1 >= monoSamples.length) break;
        // Left channel
        stereo[i * 2] = monoSamples[i];
        stereo[i * 2 + 1] = monoSamples[i + 1];
        // Right channel (same)
        stereo[i * 2 + 2] = monoSamples[i];
        stereo[i * 2 + 3] = monoSamples[i + 1];
      }
      _stdin!.add(stereo);
    } catch (e) {
      _log('Audio write error: $e');
    }
  }

  void stop() {
    _running = false;
    _broker.dispose();
    try {
      _stdin?.close();
      _paplay?.kill();
    } catch (_) {}
    _paplay = null;
    _stdin = null;
  }

  void _log(String msg) {
    DataBroker.dispatch(1, 'LogInfo', '[AudioOutput]: $msg', store: false);
  }
}

/// Linux microphone capture — uses parecord subprocess at 48kHz,
/// resamples to 32kHz, dispatches TransmitVoicePCM.
///
/// parecord is used instead of PortAudio because PortAudio's ALSA
/// capture path is broken on PipeWire systems (mmap errors).
class LinuxMicCapture implements MicCapture {
  Process? _parecord;
  bool _running = false;
  final DataBrokerClient _broker = DataBrokerClient();
  int _radioDeviceId = 0;
  StreamSubscription<List<int>>? _stdoutSub;

  /// Start capturing from the default microphone.
  Future<void> start(int radioDeviceId) async {
    if (_running) return;
    _radioDeviceId = radioDeviceId;

    try {
      _parecord = await Process.start('parecord', [
        '--format=s16le',
        '--rate=48000',
        '--channels=1',
        '--raw',
        '--latency-msec=20',
        '--stream-name=HTCommander TX',
      ]);
      _running = true;

      // Read captured audio and dispatch
      _stdoutSub = _parecord!.stdout.listen((data) {
        if (!_running) return;
        final pcm48k = Uint8List.fromList(data);

        // Resample 48kHz → 32kHz
        final pcm32k =
            AudioResampler.resample16BitMono(pcm48k, 48000, 32000);

        // Dispatch to radio for SBC encoding and transmission
        _broker.dispatch(_radioDeviceId, 'TransmitVoicePCM', pcm32k,
            store: false);
      });

      _log('Mic capture started (parecord, 48kHz → 32kHz)');
    } catch (e) {
      _log('Failed to start mic capture: $e');
      _running = false;
    }
  }

  void stop() {
    _running = false;
    _stdoutSub?.cancel();
    _stdoutSub = null;
    try {
      _parecord?.kill();
    } catch (_) {}
    _parecord = null;
    _broker.dispose();
  }

  void _log(String msg) {
    DataBroker.dispatch(1, 'LogInfo', '[MicCapture]: $msg', store: false);
  }
}
