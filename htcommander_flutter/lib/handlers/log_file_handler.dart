/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';

import '../core/data_broker_client.dart';

/// A data handler that saves log messages (LogInfo and LogError) to a file.
///
/// Port of HTCommander.Core/Utils/LogFileHandler.cs
/// Subscribes to LogInfo/LogError on device 1, writes timestamped entries to disk.
class LogFileHandler {
  final DataBrokerClient _broker = DataBrokerClient();
  IOSink? _writer;
  String? _filePath;
  bool _disposed = false;

  /// Gets the path to the log file.
  String? get filePath => _filePath;

  /// Gets whether the handler is disposed.
  bool get isDisposed => _disposed;

  LogFileHandler() {
    _broker.subscribeMultiple(1, ['LogInfo', 'LogError'], _onLogMessage);
  }

  /// Initializes the log file handler, opening the log file for writing.
  void initialize(String appDataPath) {
    _filePath = '$appDataPath/htcommander.log';
    _writer = File(_filePath!).openWrite(mode: FileMode.append);
    _writeLog('INFO', 'Log file opened: ${_formatTimestamp(DateTime.now())}');
  }

  void _onLogMessage(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! String) return;
    final level = (name == 'LogError') ? 'ERROR' : 'INFO';
    _writeLog(level, data);
  }

  void _writeLog(String level, String message) {
    if (_writer == null || _disposed) return;
    try {
      final timestamp = _formatTimestamp(DateTime.now());
      _writer!.write('[$timestamp] [$level] $message\n');
    } catch (_) {
      // Ignore write errors
    }
  }

  /// Writes a custom message directly to the log file.
  void write(String level, String message) {
    if (_disposed) throw StateError('LogFileHandler has been disposed');
    _writeLog(level, message);
  }

  /// Flushes the log file buffer.
  Future<void> flush() async {
    if (_writer != null && !_disposed) {
      try {
        await _writer!.flush();
      } catch (_) {
        // Ignore flush errors
      }
    }
  }

  /// Formats a DateTime as yyyy-MM-dd HH:mm:ss.fff.
  String _formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$y-$m-$d $h:$min:$s.$ms';
  }

  /// Disposes the handler, closing the log file and unsubscribing from the broker.
  Future<void> dispose() async {
    if (!_disposed) {
      _writeLog('INFO', 'Log file closed: ${_formatTimestamp(DateTime.now())}');
      if (_writer != null) {
        try {
          await _writer!.flush();
          await _writer!.close();
        } catch (_) {
          // Ignore close errors
        }
        _writer = null;
      }
      _broker.dispose();
      _disposed = true;
    }
  }
}
