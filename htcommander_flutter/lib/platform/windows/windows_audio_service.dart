/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../core/data_broker.dart';
import '../../core/data_broker_client.dart';
import '../../radio/audio_resampler.dart';
import '../audio_service.dart';
import 'windows_native_methods.dart';

/// Windows audio output using waveOut API from winmm.dll.
///
/// Opens waveOut at 32kHz, 16-bit, stereo. Subscribes to AudioDataAvailable
/// via DataBrokerClient and writes decoded mono PCM (duplicated to stereo)
/// using double-buffered waveOutWrite.
class WindowsAudioOutput implements AudioOutput {
  bool _running = false;
  final DataBrokerClient _broker = DataBrokerClient();

  // Native handles
  Pointer<IntPtr>? _hWaveOut;
  Pointer<Uint8>? _wfx;
  final List<Pointer<Uint8>> _waveHdrs = [];
  final List<Pointer<Uint8>> _dataBufs = [];
  int _currentBuffer = 0;

  // Audio format: 32kHz, 16-bit, stereo
  static const int _sampleRate = 32000;
  static const int _channels = 2;
  static const int _bitsPerSample = 16;
  static const int _bytesPerFrame = _channels * (_bitsPerSample ~/ 8);
  static const int _bufferFrames = 1024;
  static const int _bufferBytes = _bufferFrames * _bytesPerFrame;
  static const int _bufferCount = 2;

  @override
  Future<void> start(int radioDeviceId) async {
    if (_running) return;

    try {
      // Allocate WAVEFORMATEX using native helper
      _wfx = buildWaveFormatEx(
        channels: _channels,
        samplesPerSec: _sampleRate,
        bitsPerSample: _bitsPerSample,
      );

      // Open waveOut device
      _hWaveOut = calloc<IntPtr>();
      final result = WindowsNativeMethods.waveOutOpen(
        _hWaveOut!,
        waveMapper, // WAVE_MAPPER
        _wfx!,
        0,
        0,
        callbackNull,
      );

      if (result != mmsyserrNoError) {
        _log('waveOutOpen failed with error $result');
        calloc.free(_hWaveOut!);
        calloc.free(_wfx!);
        _hWaveOut = null;
        _wfx = null;
        return;
      }

      // Allocate double buffers
      for (var i = 0; i < _bufferCount; i++) {
        final dataBuf = calloc<Uint8>(_bufferBytes);
        final hdr = buildWaveHdr(dataBuf, _bufferBytes);

        WindowsNativeMethods.waveOutPrepareHeader(
            _hWaveOut!.value, hdr, waveHdrSize);

        _dataBufs.add(dataBuf);
        _waveHdrs.add(hdr);
      }

      _running = true;

      // Subscribe to decoded audio data from RadioAudioManager
      _broker.subscribe(radioDeviceId, 'AudioDataAvailable',
          (deviceId, name, data) {
        if (data is Uint8List && _running) {
          writePcmMono(data);
        }
      });

      _log('Audio output started (waveOut, ${_sampleRate}Hz stereo)');
    } catch (e) {
      _log('Failed to start audio output: $e');
      _running = false;
    }
  }

  @override
  void writePcmMono(Uint8List monoSamples) {
    if (!_running || _hWaveOut == null) return;

    try {
      // Duplicate mono to stereo (2 bytes per sample -> 4 bytes per frame)
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

      // Write stereo data in buffer-sized chunks
      var offset = 0;
      while (offset < stereo.length) {
        final hdr = _waveHdrs[_currentBuffer];
        final flags = readWaveHdrFlags(hdr);

        // If buffer is done playing, unprepare and re-prepare
        if (flags & whdrDone != 0) {
          WindowsNativeMethods.waveOutUnprepareHeader(
              _hWaveOut!.value, hdr, waveHdrSize);
          // Re-prepare for reuse
          WindowsNativeMethods.waveOutPrepareHeader(
              _hWaveOut!.value, hdr, waveHdrSize);
        }

        final chunk = stereo.length - offset;
        final bytesToWrite = chunk < _bufferBytes ? chunk : _bufferBytes;

        // Copy data into native buffer
        final dataBuf = _dataBufs[_currentBuffer];
        for (var i = 0; i < bytesToWrite; i++) {
          dataBuf[i] = stereo[offset + i];
        }

        // Update dwBufferLength in the WAVEHDR (bytes 8-11)
        hdr[8] = bytesToWrite & 0xFF;
        hdr[9] = (bytesToWrite >> 8) & 0xFF;
        hdr[10] = (bytesToWrite >> 16) & 0xFF;
        hdr[11] = (bytesToWrite >> 24) & 0xFF;

        WindowsNativeMethods.waveOutWrite(
            _hWaveOut!.value, hdr, waveHdrSize);

        offset += bytesToWrite;
        _currentBuffer = (_currentBuffer + 1) % _bufferCount;
      }
    } catch (e) {
      _log('Audio write error: $e');
    }
  }

  @override
  void stop() {
    _running = false;
    _broker.dispose();

    if (_hWaveOut != null) {
      try {
        WindowsNativeMethods.waveOutReset(_hWaveOut!.value);

        // Unprepare and free buffers
        for (var i = 0; i < _waveHdrs.length; i++) {
          WindowsNativeMethods.waveOutUnprepareHeader(
              _hWaveOut!.value, _waveHdrs[i], waveHdrSize);
          calloc.free(_dataBufs[i]);
          calloc.free(_waveHdrs[i]);
        }

        WindowsNativeMethods.waveOutClose(_hWaveOut!.value);
        calloc.free(_hWaveOut!);
      } catch (_) {}

      if (_wfx != null) {
        calloc.free(_wfx!);
        _wfx = null;
      }

      _hWaveOut = null;
      _waveHdrs.clear();
      _dataBufs.clear();
      _currentBuffer = 0;
    }
  }

  void _log(String msg) {
    DataBroker.dispatch(1, 'LogInfo', '[AudioOutput]: $msg', store: false);
  }
}

/// Windows microphone capture using waveIn API from winmm.dll.
///
/// Opens waveIn at 48kHz, 16-bit, mono. Uses polling-based capture with
/// multiple buffers. Resamples 48kHz to 32kHz and dispatches
/// TransmitVoicePCM via DataBrokerClient.
class WindowsMicCapture implements MicCapture {
  bool _running = false;
  final DataBrokerClient _broker = DataBrokerClient();
  int _radioDeviceId = 0;

  // Native handles
  Pointer<IntPtr>? _hWaveIn;
  Pointer<Uint8>? _wfx;
  final List<Pointer<Uint8>> _waveHdrs = [];
  final List<Pointer<Uint8>> _dataBufs = [];

  // Capture format: 48kHz, 16-bit, mono
  static const int _captureSampleRate = 48000;
  static const int _captureChannels = 1;
  static const int _captureBitsPerSample = 16;
  static const int _captureBytesPerFrame =
      _captureChannels * (_captureBitsPerSample ~/ 8);
  // ~20ms of audio per buffer at 48kHz
  static const int _captureBufferFrames = 960;
  static const int _captureBufferBytes =
      _captureBufferFrames * _captureBytesPerFrame;
  static const int _captureBufferCount = 4;

  @override
  Future<void> start(int radioDeviceId) async {
    if (_running) return;
    _radioDeviceId = radioDeviceId;

    try {
      // Allocate WAVEFORMATEX using native helper
      _wfx = buildWaveFormatEx(
        channels: _captureChannels,
        samplesPerSec: _captureSampleRate,
        bitsPerSample: _captureBitsPerSample,
      );

      // Open waveIn device
      _hWaveIn = calloc<IntPtr>();
      final result = WindowsNativeMethods.waveInOpen(
        _hWaveIn!,
        waveMapper, // WAVE_MAPPER
        _wfx!,
        0,
        0,
        callbackNull,
      );

      if (result != mmsyserrNoError) {
        _log('waveInOpen failed with error $result');
        calloc.free(_hWaveIn!);
        calloc.free(_wfx!);
        _hWaveIn = null;
        _wfx = null;
        return;
      }

      // Allocate capture buffers
      for (var i = 0; i < _captureBufferCount; i++) {
        final dataBuf = calloc<Uint8>(_captureBufferBytes);
        final hdr = buildWaveHdr(dataBuf, _captureBufferBytes);

        WindowsNativeMethods.waveInPrepareHeader(
            _hWaveIn!.value, hdr, waveHdrSize);
        WindowsNativeMethods.waveInAddBuffer(
            _hWaveIn!.value, hdr, waveHdrSize);

        _dataBufs.add(dataBuf);
        _waveHdrs.add(hdr);
      }

      _running = true;

      // Start capture
      WindowsNativeMethods.waveInStart(_hWaveIn!.value);

      // Poll for completed buffers
      _pollCaptureBuffers();

      _log(
          'Mic capture started (waveIn, ${_captureSampleRate}Hz -> 32kHz)');
    } catch (e) {
      _log('Failed to start mic capture: $e');
      _running = false;
    }
  }

  /// Polls waveIn buffers for completed data and re-queues them.
  Future<void> _pollCaptureBuffers() async {
    while (_running && _hWaveIn != null) {
      for (var i = 0; i < _waveHdrs.length; i++) {
        final hdr = _waveHdrs[i];
        final flags = readWaveHdrFlags(hdr);

        // Check WHDR_DONE flag
        if (flags & whdrDone != 0) {
          final bytesRecorded = readWaveHdrBytesRecorded(hdr);
          if (bytesRecorded > 0) {
            // Copy captured data from native buffer
            final pcm48k = Uint8List(bytesRecorded);
            final dataBuf = _dataBufs[i];
            for (var j = 0; j < bytesRecorded; j++) {
              pcm48k[j] = dataBuf[j];
            }

            // Resample 48kHz -> 32kHz
            final pcm32k =
                AudioResampler.resample16BitMono(pcm48k, 48000, 32000);

            // Dispatch to radio for SBC encoding and transmission
            _broker.dispatch(_radioDeviceId, 'TransmitVoicePCM', pcm32k,
                store: false);
          }

          // Unprepare, reset, re-prepare and re-queue the buffer
          WindowsNativeMethods.waveInUnprepareHeader(
              _hWaveIn!.value, hdr, waveHdrSize);

          // Clear dwFlags (bytes 24-27) and dwBytesRecorded (bytes 12-15)
          hdr[24] = 0;
          hdr[25] = 0;
          hdr[26] = 0;
          hdr[27] = 0;
          hdr[12] = 0;
          hdr[13] = 0;
          hdr[14] = 0;
          hdr[15] = 0;

          WindowsNativeMethods.waveInPrepareHeader(
              _hWaveIn!.value, hdr, waveHdrSize);
          WindowsNativeMethods.waveInAddBuffer(
              _hWaveIn!.value, hdr, waveHdrSize);
        }
      }

      // Yield to event loop between polls (~5ms)
      await Future.delayed(const Duration(milliseconds: 5));
    }
  }

  @override
  void stop() {
    _running = false;

    if (_hWaveIn != null) {
      try {
        WindowsNativeMethods.waveInStop(_hWaveIn!.value);
        WindowsNativeMethods.waveInReset(_hWaveIn!.value);

        // Unprepare and free buffers
        for (var i = 0; i < _waveHdrs.length; i++) {
          WindowsNativeMethods.waveInUnprepareHeader(
              _hWaveIn!.value, _waveHdrs[i], waveHdrSize);
          calloc.free(_dataBufs[i]);
          calloc.free(_waveHdrs[i]);
        }

        WindowsNativeMethods.waveInClose(_hWaveIn!.value);
        calloc.free(_hWaveIn!);
      } catch (_) {}

      if (_wfx != null) {
        calloc.free(_wfx!);
        _wfx = null;
      }

      _hWaveIn = null;
      _waveHdrs.clear();
      _dataBufs.clear();
    }

    _broker.dispose();
  }

  void _log(String msg) {
    DataBroker.dispatch(1, 'LogInfo', '[MicCapture]: $msg', store: false);
  }
}
