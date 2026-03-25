/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';

/// Holds progress information for a file download.
class DownloadProgressInfo {
  final int bytesDownloaded;
  final int? totalBytes;
  final bool isComplete;
  final bool isCancelled;
  final String? error;

  /// Returns the download percentage (0-100), or 0 if total size is unknown.
  double get percentage =>
      (totalBytes != null && totalBytes! > 0)
          ? bytesDownloaded / totalBytes! * 100.0
          : 0.0;

  /// Constructor for progress updates.
  const DownloadProgressInfo({
    required this.bytesDownloaded,
    this.totalBytes,
    this.isComplete = false,
    this.isCancelled = false,
    this.error,
  });
}

/// Downloads a file from HTTP with progress reporting.
///
/// Port of HTCommander.Core/radio/FileDownloader.cs
class FileDownloader {
  // HttpClient is reused across downloads to avoid socket exhaustion.
  static final HttpClient _httpClient = HttpClient();

  bool _cancelled = false;

  /// Downloads a file from [url] to [outputPath], reporting progress via [onProgress].
  ///
  /// Auto-creates the output directory if it does not exist.
  /// Cleans up partial files on error or cancellation.
  Future<void> downloadFile(
    String url,
    String outputPath, {
    void Function(DownloadProgressInfo)? onProgress,
  }) async {
    int totalBytesRead = 0;
    int? totalDownloadSize;
    bool downloadFinishedGracefully = false;

    try {
      // Ensure the directory exists
      final directory = File(outputPath).parent;
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }

      // Send GET request, read headers first
      final request = await _httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      totalDownloadSize = response.contentLength > 0
          ? response.contentLength
          : null;
      onProgress?.call(DownloadProgressInfo(
        bytesDownloaded: 0,
        totalBytes: totalDownloadSize,
      ));

      // Stream response to file
      final file = File(outputPath);
      final sink = file.openWrite();

      try {
        await for (final chunk in response) {
          if (_cancelled) {
            onProgress?.call(DownloadProgressInfo(
              bytesDownloaded: totalBytesRead,
              totalBytes: totalDownloadSize,
              isCancelled: true,
            ));
            break;
          }

          sink.add(chunk);
          totalBytesRead += chunk.length;

          onProgress?.call(DownloadProgressInfo(
            bytesDownloaded: totalBytesRead,
            totalBytes: totalDownloadSize,
          ));
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (!_cancelled) {
        onProgress?.call(DownloadProgressInfo(
          bytesDownloaded: totalBytesRead,
          totalBytes: totalDownloadSize,
          isComplete: true,
        ));
        downloadFinishedGracefully = true;
      }
    } catch (e) {
      if (!_cancelled) {
        onProgress?.call(DownloadProgressInfo(
          bytesDownloaded: totalBytesRead,
          totalBytes: totalDownloadSize,
          error: e.toString(),
        ));
      }
    } finally {
      // Clean up partially downloaded file if cancelled or errored
      if (!downloadFinishedGracefully) {
        try {
          final file = File(outputPath);
          if (file.existsSync()) {
            file.deleteSync();
          }
        } catch (_) {
          // Ignore cleanup errors
        }
      }
    }
  }

  /// Requests cancellation of the current download.
  void cancel() {
    _cancelled = true;
  }
}
