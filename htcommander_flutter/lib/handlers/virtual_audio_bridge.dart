/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'dart:typed_data';

import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../radio/audio_resampler.dart';
import '../platform/linux/linux_virtual_audio_provider.dart';

/// DataBroker handler that bridges radio audio to PulseAudio virtual devices.
///
/// RX path: Radio audio → resample 32kHz→48kHz → virtual sink (apps hear radio).
/// TX path: Virtual sink monitor → resample 48kHz→32kHz → radio transmit.
///
/// Port of HTCommander.Core/Utils/VirtualAudioBridge.cs
class VirtualAudioBridge {
  final DataBrokerClient _broker = DataBrokerClient();
  LinuxVirtualAudioProvider? _provider;
  bool _running = false;
  int _activeRadioId = -1;

  VirtualAudioBridge() {
    _broker.subscribe(0, 'VirtualAudioEnabled', _onSettingChanged);
    _broker.subscribe(1, 'ConnectedRadios', _onConnectedRadiosChanged);
    _broker.subscribe(
        DataBroker.allDevices, 'AudioDataAvailable', _onAudioDataAvailable);

    // Start immediately if already enabled
    if (DataBroker.getValue<int>(0, 'VirtualAudioEnabled', 0) == 1) {
      _start();
    }
  }

  void _onSettingChanged(int deviceId, String name, Object? data) {
    final enabled = (data is int) ? data : 0;
    if (enabled == 1 && !_running) {
      _start();
    } else if (enabled != 1 && _running) {
      _stop();
    }
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (data is! List) return;
    _activeRadioId = -1;
    for (final item in data) {
      if (item is Map) {
        final id = item['DeviceId'];
        if (id is int && id > 0) {
          _activeRadioId = id;
          break;
        }
      }
    }
  }

  void _onAudioDataAvailable(int deviceId, String name, Object? data) {
    if (!_running || _provider == null) return;
    if (deviceId < 100) return; // Not a radio device

    if (data is! Map) return;
    // Only forward RX audio (skip TX loopback)
    if (data['Transmit'] == true) return;

    final pcm = data['Data'];
    if (pcm is! Uint8List) return;

    // Resample 32kHz → 48kHz for desktop apps
    final resampled = AudioResampler.resample16BitMono(pcm, 32000, 48000);
    _provider!.writeSamples(resampled);
  }

  void _onTxDataAvailable(Uint8List data, int length) {
    if (!_running) return;

    // Find active radio
    final radioId = _activeRadioId > 0 ? _activeRadioId : _findFirstRadio();
    if (radioId < 0) return;

    // Only forward if external PTT is active
    final pttState = _broker.getValue<Object?>(1, 'ExternalPttState', null);
    if (pttState != true) return;

    // Resample 48kHz → 32kHz for radio
    final resampled = AudioResampler.resample16BitMono(data, 48000, 32000);
    _broker.dispatch(radioId, 'TransmitVoicePCM', resampled, store: false);
  }

  int _findFirstRadio() {
    final radios = DataBroker.getValue<Object?>(1, 'ConnectedRadios', null);
    if (radios is! List) return -1;
    for (final item in radios) {
      if (item is Map) {
        final id = item['DeviceId'];
        if (id is int && id > 0) return id;
      }
    }
    return -1;
  }

  Future<void> _start() async {
    if (_running) return;
    if (!Platform.isLinux) return;

    final provider = LinuxVirtualAudioProvider();
    final success = await provider.create(48000);
    if (!success) return;

    provider.onTxDataAvailable = _onTxDataAvailable;
    _provider = provider;
    _running = true;
    _broker.logInfo('Virtual audio bridge started');
  }

  Future<void> _stop() async {
    if (!_running) return;
    _running = false;
    await _provider?.destroy();
    _provider = null;
    _broker.logInfo('Virtual audio bridge stopped');
  }

  void dispose() {
    _stop();
    _broker.dispose();
  }
}
