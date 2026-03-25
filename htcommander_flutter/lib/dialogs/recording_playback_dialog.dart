import 'dart:io';
import 'package:flutter/material.dart';

/// Dialog for playing back a recorded WAV audio file.
class RecordingPlaybackDialog extends StatefulWidget {
  final String filePath;

  const RecordingPlaybackDialog({super.key, required this.filePath});

  @override
  State<RecordingPlaybackDialog> createState() =>
      _RecordingPlaybackDialogState();
}

class _RecordingPlaybackDialogState extends State<RecordingPlaybackDialog> {
  bool _isPlaying = false;
  double _progress = 0;
  String _statusText = '';
  Process? _playProcess;

  @override
  void initState() {
    super.initState();
    final file = File(widget.filePath);
    if (file.existsSync()) {
      final stat = file.statSync();
      _statusText = _formatSize(stat.size);
    } else {
      _statusText = 'File not found';
    }
  }

  @override
  void dispose() {
    _stopPlayback();
    super.dispose();
  }

  Future<void> _startPlayback() async {
    if (_isPlaying) return;

    setState(() {
      _isPlaying = true;
      _progress = 0;
      _statusText = 'Playing...';
    });

    try {
      if (Platform.isLinux) {
        // Use paplay for Linux audio playback
        _playProcess = await Process.start('paplay', [
          '--format=s16le',
          '--rate=32000',
          '--channels=1',
          widget.filePath,
        ]);
      } else if (Platform.isWindows) {
        // Use PowerShell for Windows audio playback
        _playProcess = await Process.start('powershell', [
          '-Command',
          '(New-Object Media.SoundPlayer "${widget.filePath}").PlaySync()',
        ]);
      } else {
        // Android / other — not yet supported via subprocess
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _statusText = 'Playback not available on this platform';
          });
        }
        return;
      }

      _playProcess!.exitCode.then((_) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _progress = 1.0;
            _statusText = 'Playback complete';
          });
        }
        _playProcess = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _statusText = 'Playback error';
        });
      }
    }
  }

  void _stopPlayback() {
    _playProcess?.kill();
    _playProcess = null;
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _statusText = 'Stopped';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fileName = widget.filePath.split('/').last;

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('RECORDING PLAYBACK',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              Text(fileName,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface)),
              const SizedBox(height: 8),
              Text(_statusText,
                  style: TextStyle(
                      fontSize: 10, color: colors.onSurfaceVariant)),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _isPlaying ? null : _progress,
                backgroundColor: colors.surfaceContainerLow,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_isPlaying)
                    FilledButton.tonal(
                      onPressed: _startPlayback,
                      child: const Text('PLAY',
                          style: TextStyle(fontSize: 10, letterSpacing: 1)),
                    )
                  else
                    FilledButton.tonal(
                      onPressed: _stopPlayback,
                      child: const Text('STOP',
                          style: TextStyle(fontSize: 10, letterSpacing: 1)),
                    ),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('CLOSE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              color: colors.onSurfaceVariant))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
