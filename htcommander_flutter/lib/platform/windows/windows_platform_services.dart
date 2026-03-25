/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';

import '../audio_service.dart';
import '../bluetooth_service.dart';
import 'windows_audio_service.dart';
import 'windows_audio_transport.dart';
import 'windows_bluetooth.dart';

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

/// Windows platform services using Winsock2 RFCOMM and winmm.dll audio.
class WindowsPlatformServices extends PlatformServices {
  @override
  RadioBluetoothTransport createRadioBluetooth(String macAddress) {
    return WindowsRadioBluetooth(macAddress);
  }

  @override
  RadioAudioTransport createRadioAudioTransport() {
    return WindowsRadioAudioTransport();
  }

  @override
  AudioOutput createAudioOutput() => WindowsAudioOutput();

  @override
  MicCapture createMicCapture() => WindowsMicCapture();

  /// Scans for compatible paired Bluetooth devices using PowerShell.
  ///
  /// Enumerates paired Bluetooth devices via Get-PnpDevice and filters by
  /// known radio device names.
  @override
  Future<List<CompatibleDevice>> scanForDevices() async {
    final devices = <CompatibleDevice>[];
    final seenMacs = <String>{};

    try {
      // Use PowerShell to enumerate paired Bluetooth devices.
      // Get-PnpDevice queries the Windows device manager for Bluetooth devices.
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"Get-PnpDevice -Class Bluetooth | Where-Object { $_.Status -eq 'OK' } | "
            r"Select-Object FriendlyName, InstanceId | "
            r"ForEach-Object { $_.FriendlyName + '|' + $_.InstanceId }",
      ]).timeout(const Duration(seconds: 10));

      if (result.exitCode != 0) return devices;

      final output = result.stdout as String;
      final lines = output.split('\n');

      // InstanceId format includes BT address as 12-char hex:
      // BTHENUM\{...}_DEVCLASS\{...}&BTADDR_XXXXXXXXXXXX
      // or BTHENUM\Dev_XXXXXXXXXXXX\...
      final macRegex = RegExp(r'[_&]([0-9A-Fa-f]{12})(?:\\|$)');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        final parts = trimmed.split('|');
        if (parts.length < 2) continue;

        final name = parts[0].trim();
        final instanceId = parts[1].trim();

        // Check if device name matches a known radio
        if (!_targetDeviceNames.contains(name)) continue;

        // Extract MAC address from InstanceId
        final macMatch = macRegex.firstMatch(instanceId);
        if (macMatch == null) continue;

        final mac = macMatch.group(1)!.toUpperCase();
        if (seenMacs.contains(mac)) continue;
        seenMacs.add(mac);

        devices.add(CompatibleDevice(name, mac));
      }
    } catch (_) {
      // PowerShell not available or failed
    }

    return devices;
  }
}
