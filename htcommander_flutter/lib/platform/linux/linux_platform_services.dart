import 'dart:io';

import '../../platform/audio_service.dart';
import '../../platform/bluetooth_service.dart';
import 'linux_audio_service.dart';
import 'linux_audio_transport.dart';
import 'linux_bluetooth.dart';

/// Known device names for compatible Bluetooth radios.
const List<String> _targetDeviceNames = [
  'UV-PRO',
  'UV-50PRO',
  'GA-5WB',
  'VR-N75',
  'VR-N76',
  'VR-N7500',
  'VR-N7600',
  'RT-660',
];

/// Linux platform services using native RFCOMM sockets and BlueZ CLI tools.
class LinuxPlatformServices extends PlatformServices {
  @override
  RadioBluetoothTransport createRadioBluetooth(String macAddress) {
    return LinuxRadioBluetooth(macAddress);
  }

  @override
  RadioAudioTransport createRadioAudioTransport() {
    return LinuxRadioAudioTransport();
  }

  @override
  AudioOutput createAudioOutput() => LinuxAudioOutput();

  @override
  MicCapture createMicCapture() => LinuxMicCapture();

  /// Scans for compatible Bluetooth devices using `bluetoothctl devices`.
  ///
  /// Parses output lines of the form:
  ///   Device XX:XX:XX:XX:XX:XX DeviceName
  @override
  Future<List<CompatibleDevice>> scanForDevices() async {
    final devices = <CompatibleDevice>[];
    final seenMacs = <String>{};

    try {
      final result = await Process.run('bluetoothctl', ['devices']);
      if (result.exitCode != 0) return devices;

      final output = result.stdout as String;
      final lines = output.split('\n');
      final deviceRegex =
          RegExp(r'^Device\s+([0-9A-Fa-f:]{17})\s+(.+)$');

      for (final line in lines) {
        final match = deviceRegex.firstMatch(line.trim());
        if (match == null) continue;

        final macColon = match.group(1)!;
        final name = match.group(2)!.trim();

        if (!_targetDeviceNames.contains(name)) continue;

        final mac = macColon.replaceAll(':', '').toUpperCase();
        if (seenMacs.contains(mac)) continue;
        seenMacs.add(mac);

        devices.add(CompatibleDevice(name, mac));
      }
    } catch (_) {
      // bluetoothctl not available or failed
    }

    return devices;
  }
}
