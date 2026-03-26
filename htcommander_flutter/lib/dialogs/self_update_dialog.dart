import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Dialog for checking GitHub releases for app updates.
class SelfUpdateDialog extends StatefulWidget {
  final String currentVersion;

  const SelfUpdateDialog({super.key, required this.currentVersion});

  @override
  State<SelfUpdateDialog> createState() => _SelfUpdateDialogState();
}

class _SelfUpdateDialogState extends State<SelfUpdateDialog> {
  String _status = 'Checking for updates...';
  String? _latestVersion;
  String? _releaseUrl;
  bool _checking = true;
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..userAgent = 'HTCommander-X/${widget.currentVersion}';

      final request = await client.getUrl(Uri.parse(
          'https://api.github.com/repos/dikei100/HTCommander-X/releases/latest'));
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close();

      if (response.statusCode != 200) {
        setState(() {
          _status = 'Could not check for updates (HTTP ${response.statusCode})';
          _checking = false;
        });
        await response.drain<void>();
        client.close();
        return;
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      client.close();

      final tagName = json['tag_name'] as String? ?? '';
      final htmlUrl = json['html_url'] as String? ?? '';

      // Parse version from tag (strip leading 'v')
      final latest = tagName.startsWith('v') ? tagName.substring(1) : tagName;

      // Validate URL is from github.com
      final uri = Uri.tryParse(htmlUrl);
      final isValidUrl = uri != null &&
          uri.scheme == 'https' &&
          uri.host == 'github.com' &&
          uri.path.startsWith('/dikei100/HTCommander-X');

      _latestVersion = latest;
      _releaseUrl = isValidUrl ? htmlUrl : null;
      _updateAvailable = _isNewerVersion(latest, widget.currentVersion);

      setState(() {
        if (_updateAvailable) {
          _status = 'Update available: v$latest (current: v${widget.currentVersion})';
        } else {
          _status = 'You are running the latest version (v${widget.currentVersion})';
        }
        _checking = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Could not check for updates';
        _checking = false;
      });
    }
  }

  /// Compares semantic versions. Returns true if latest > current.
  bool _isNewerVersion(String latest, String current) {
    final latestParts = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final currentParts = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CHECK FOR UPDATES', style: TextStyle(fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                  color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (_checking)
                const Center(child: CircularProgressIndicator())
              else ...[
                Icon(
                  _updateAvailable ? Icons.system_update : Icons.check_circle,
                  size: 32,
                  color: _updateAvailable ? colors.primary : Colors.green,
                ),
                const SizedBox(height: 12),
                Text(_status, style: TextStyle(fontSize: 12,
                    color: colors.onSurface)),
              ],
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (_updateAvailable && _releaseUrl != null)
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _releaseUrl),
                    child: const Text('VIEW RELEASE', style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
                  ),
                const SizedBox(width: 8),
                TextButton(onPressed: () => Navigator.pop(context),
                    child: Text('CLOSE', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1,
                        color: colors.onSurfaceVariant))),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
