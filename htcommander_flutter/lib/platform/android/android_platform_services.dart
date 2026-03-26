import 'package:flutter/services.dart';

import '../../core/data_broker.dart';
import '../../platform/audio_service.dart';
import '../../platform/bluetooth_service.dart';
import 'android_audio_service.dart';
import 'android_audio_transport.dart';
import 'android_bluetooth.dart';

/// Known device names for compatible Bluetooth radios.
const List<String> targetDeviceNames = [
  'UV-PRO',
  'UV-50PRO',
  'GA-5WB',
  'VR-N75',
  'VR-N76',
  'VR-N7500',
  'VR-N7600',
  'RT-660',
];

/// Android platform services using Bluetooth Classic RFCOMM via MethodChannel.
class AndroidPlatformServices extends PlatformServices {
  static const _btChannel = MethodChannel('com.htcommander/bluetooth');

  AndroidPlatformServices() {
    // Listen for permission denial callbacks from Kotlin MainActivity.
    _btChannel.setMethodCallHandler((call) async {
      if (call.method == 'permissionsDenied') {
        final denied = (call.arguments as List?)?.cast<String>() ?? [];
        DataBroker.dispatch(1, 'PermissionsDenied', denied, store: false);
      }
    });
  }

  @override
  RadioBluetoothTransport createRadioBluetooth(String macAddress) {
    return AndroidRadioBluetooth(macAddress);
  }

  @override
  RadioAudioTransport createRadioAudioTransport() {
    return AndroidRadioAudioTransport();
  }

  @override
  AudioOutput createAudioOutput() => AndroidAudioOutput();

  @override
  MicCapture createMicCapture() => AndroidMicCapture();

  /// Scans for paired Bluetooth devices filtered by compatible radio names.
  @override
  Future<List<CompatibleDevice>> scanForDevices() async {
    try {
      final result = await _btChannel.invokeMethod<List<dynamic>>('scanDevices');
      if (result == null) return [];

      final devices = <CompatibleDevice>[];
      final seenMacs = <String>{};

      for (final item in result) {
        final map = Map<String, dynamic>.from(item as Map);
        final name = map['name'] as String? ?? '';
        final mac = map['mac'] as String? ?? '';

        if (!targetDeviceNames.contains(name)) continue;
        final normalized =
            mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
        if (seenMacs.contains(normalized)) continue;
        seenMacs.add(normalized);

        devices.add(CompatibleDevice(name, normalized));
      }

      return devices;
    } on PlatformException {
      return [];
    }
  }
}
