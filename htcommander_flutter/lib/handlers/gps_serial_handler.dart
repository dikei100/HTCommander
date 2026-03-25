import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../radio/gps/gps_data.dart';

/// Data Broker handler that reads NMEA sentences from a GPS serial port.
/// Reads the "GpsSerialPort" and "GpsBaudRate" settings from device 0.
/// Parses incoming NMEA sentences and dispatches a [GpsData] object on
/// Device 1 under key "GpsData".
///
/// Port of HTCommander.Core/Gps/GpsSerialHandler.cs
class GpsSerialHandler {
  final DataBrokerClient _broker = DataBrokerClient();
  RandomAccessFile? _port;
  StreamSubscription<String>? _readSubscription;
  Timer? _readTimer;
  final StringBuffer _lineBuffer = StringBuffer();
  String _currentPortName = '';
  int _currentBaudRate = 4800;
  GpsData _gpsData = GpsData();
  bool _isCommunicating = false;
  bool _disposed = false;

  GpsSerialHandler() {
    // Subscribe to GPS serial port setting changes on device 0
    _broker.subscribe(0, 'GpsSerialPort', _onSettingChanged);
    _broker.subscribe(0, 'GpsBaudRate', _onSettingChanged);

    // Read current settings and open port if already configured
    _currentPortName = DataBroker.getValue<String>(0, 'GpsSerialPort', 'None');
    _currentBaudRate = DataBroker.getValue<int>(0, 'GpsBaudRate', 4800);
    _startPort(_currentPortName, _currentBaudRate);
  }

  // ------------------------------------------------------------------
  // Settings change handler
  // ------------------------------------------------------------------

  void _onSettingChanged(int deviceId, String name, Object? data) {
    final newPort = DataBroker.getValue<String>(0, 'GpsSerialPort', 'None');
    final newBaud = DataBroker.getValue<int>(0, 'GpsBaudRate', 4800);

    // Only restart if something actually changed
    if (newPort == _currentPortName && newBaud == _currentBaudRate) return;

    _currentPortName = newPort;
    _currentBaudRate = newBaud;

    // Close previous port (dispatches "Disconnected")
    _stopPort();

    final portConfigured = _currentPortName.isNotEmpty &&
        _currentPortName != 'None';
    if (portConfigured) {
      _broker.dispatch(1, 'GpsStatus', 'Connecting', store: true);
      _startPort(_currentPortName, _currentBaudRate);
    } else {
      _broker.dispatch(1, 'GpsStatus', 'Disabled', store: true);
    }
  }

  // ------------------------------------------------------------------
  // Serial port lifecycle
  // ------------------------------------------------------------------

  void _startPort(String portName, int baudRate) {
    if (portName.isEmpty || portName == 'None') return;

    // Configure baud rate via stty before opening (Linux)
    _startPortAsync(portName, baudRate);
  }

  Future<void> _startPortAsync(String portName, int baudRate) async {
    // Serial port configuration requires stty (Linux/macOS only)
    if (!Platform.isLinux && !Platform.isMacOS) {
      _broker.dispatch(1, 'GpsStatus', 'PortError', store: true);
      return;
    }

    try {
      // Configure serial port via stty (Linux)
      final sttyResult = await Process.run('stty', [
        '-F', portName,
        baudRate.toString(),
        'raw',
        '-echo',
        '-echoe',
        '-echok',
        'cs8',
        '-cstopb',
        '-parenb',
      ]);
      if (sttyResult.exitCode != 0) {
        _broker.dispatch(1, 'GpsStatus', 'PortError', store: true);
        return;
      }
    } catch (e) {
      _broker.dispatch(1, 'GpsStatus', 'PortError', store: true);
      return;
    }

    // Staleness check
    if (_disposed || _currentPortName != portName) return;

    try {
      final file = File(portName);
      _port = await file.open(mode: FileMode.read);
    } catch (e) {
      _broker.dispatch(1, 'GpsStatus', 'PortError', store: true);
      return;
    }

    // Staleness check
    if (_disposed || _currentPortName != portName) {
      _closePort();
      return;
    }

    // Start periodic read loop (non-blocking reads every 100ms)
    _readTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _readData();
    });
  }

  Future<void> _readData() async {
    if (_disposed || _port == null) return;
    try {
      final bytes = _port!.readSync(1024);
      if (bytes.isEmpty) return;
      final text = ascii.decode(bytes, allowInvalid: true);
      for (var i = 0; i < text.length; i++) {
        final ch = text[i];
        if (ch == '\n') {
          final line = _lineBuffer.toString().trimRight();
          _lineBuffer.clear();
          if (line.isNotEmpty) _processNmeaLine(line);
        } else if (ch != '\r') {
          _lineBuffer.write(ch);
        }
      }
    } catch (_) {
      // Read error — port may have been disconnected
    }
  }

  void _stopPort() {
    _readTimer?.cancel();
    _readTimer = null;
    _readSubscription?.cancel();
    _readSubscription = null;
    _closePort();
    _lineBuffer.clear();
    _gpsData = GpsData();
    _isCommunicating = false;
    _broker.dispatch(1, 'GpsData', null, store: true);
    _broker.dispatch(1, 'GpsStatus', 'Disconnected', store: true);
  }

  void _closePort() {
    try {
      _port?.closeSync();
    } catch (_) {}
    _port = null;
  }

  // ------------------------------------------------------------------
  // NMEA processing
  // ------------------------------------------------------------------

  void _processNmeaLine(String line) {
    // NMEA sentences start with '$' and end with '*XX' checksum
    if (line.length < 6 || line[0] != '\$') return;

    // Validate checksum
    final starIdx = line.lastIndexOf('*');
    String body = line;
    if (starIdx > 0 && starIdx < line.length - 1) {
      if (!_validateChecksum(line, starIdx)) return;
      body = line.substring(0, starIdx);
    }

    final fields = body.split(',');
    if (fields.length < 2) return;

    // First valid sentence — notify listeners the device is alive
    if (!_isCommunicating) {
      _isCommunicating = true;
      _broker.dispatch(1, 'GpsStatus', 'Communicating', store: true);
    }

    // Accept both GP (single-constellation) and GN (multi-constellation)
    final type = fields[0].length >= 6 ? fields[0].substring(1) : '';

    if (type == 'GPRMC' || type == 'GNRMC') {
      _parseRmc(fields);
    } else if (type == 'GPGGA' || type == 'GNGGA') {
      _parseGga(fields);
    }
  }

  /// Validates the NMEA XOR checksum.
  static bool _validateChecksum(String sentence, int starIdx) {
    try {
      var computed = 0;
      for (var i = 1; i < starIdx; i++) {
        computed ^= sentence.codeUnitAt(i);
      }
      computed &= 0xFF;
      final hexStr = sentence.substring(starIdx + 1, starIdx + 3);
      final expected = int.tryParse(hexStr, radix: 16);
      return expected != null && computed == expected;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // $GPRMC / $GNRMC
  // ------------------------------------------------------------------
  void _parseRmc(List<String> f) {
    if (f.length < 10) return;

    final isFixed = f.length > 2 && f[2] == 'A';
    _gpsData.isFixed = isFixed;

    if (f[1].isNotEmpty && f[1].length >= 6) {
      _gpsData.gpsTime = _parseNmeaDateTime(f[1], f.length > 9 ? f[9] : '');
    }

    if (f[3].isNotEmpty && f[4].isNotEmpty) {
      var lat = _nmeaDegreesToDecimal(f[3]);
      if (f[4] == 'S') lat = -lat;
      _gpsData.latitude = lat;
    }

    if (f[5].isNotEmpty && f[6].isNotEmpty) {
      var lon = _nmeaDegreesToDecimal(f[5]);
      if (f[6] == 'W') lon = -lon;
      _gpsData.longitude = lon;
    }

    if (f[7].isNotEmpty) {
      final speed = double.tryParse(f[7]);
      if (speed != null) _gpsData.speed = speed;
    }

    if (f[8].isNotEmpty) {
      final heading = double.tryParse(f[8]);
      if (heading != null) _gpsData.heading = heading;
    }

    _broker.dispatch(1, 'GpsData', _gpsData, store: true);
  }

  // ------------------------------------------------------------------
  // $GPGGA / $GNGGA
  // ------------------------------------------------------------------
  void _parseGga(List<String> f) {
    if (f.length < 10) return;

    if (f[2].isNotEmpty && f[3].isNotEmpty) {
      var lat = _nmeaDegreesToDecimal(f[2]);
      if (f[3] == 'S') lat = -lat;
      _gpsData.latitude = lat;
    }

    if (f[4].isNotEmpty && f[5].isNotEmpty) {
      var lon = _nmeaDegreesToDecimal(f[4]);
      if (f[5] == 'W') lon = -lon;
      _gpsData.longitude = lon;
    }

    if (f[6].isNotEmpty) {
      final fq = int.tryParse(f[6]);
      if (fq != null) _gpsData.fixQuality = fq;
    }

    if (f[7].isNotEmpty) {
      final sats = int.tryParse(f[7]);
      if (sats != null) _gpsData.satellites = sats;
    }

    if (f.length > 9 && f[9].isNotEmpty) {
      final alt = double.tryParse(f[9]);
      if (alt != null) _gpsData.altitude = alt;
    }

    _broker.dispatch(1, 'GpsData', _gpsData, store: true);
  }

  // ------------------------------------------------------------------
  // NMEA helpers
  // ------------------------------------------------------------------

  static double _nmeaDegreesToDecimal(String nmea) {
    if (nmea.isEmpty) return 0.0;
    final raw = double.tryParse(nmea);
    if (raw == null) return 0.0;
    final degrees = raw ~/ 100;
    final minutes = raw - degrees * 100.0;
    return degrees + minutes / 60.0;
  }

  static DateTime _parseNmeaDateTime(String timeStr, String dateStr) {
    try {
      if (timeStr.length < 6) {
        return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
      final h = int.parse(timeStr.substring(0, 2));
      final m = int.parse(timeStr.substring(2, 4));
      final s = double.parse(timeStr.substring(4));
      final sec = s.truncate();
      final ms = ((s - sec) * 1000).round();

      if (dateStr.isNotEmpty && dateStr.length == 6) {
        final day = int.parse(dateStr.substring(0, 2));
        final mon = int.parse(dateStr.substring(2, 4));
        final yr = 2000 + int.parse(dateStr.substring(4, 6));
        return DateTime.utc(yr, mon, day, h, m, sec, ms);
      }

      final today = DateTime.now().toUtc();
      return DateTime.utc(today.year, today.month, today.day, h, m, sec, ms);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
  }

  // ------------------------------------------------------------------
  // Disposal
  // ------------------------------------------------------------------

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopPort();
    _broker.dispose();
  }
}
