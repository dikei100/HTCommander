import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Result from the SSTV send dialog.
class SstvSendResult {
  final String imagePath;
  final String modeName;
  final int width;
  final int height;

  const SstvSendResult({
    required this.imagePath,
    required this.modeName,
    required this.width,
    required this.height,
  });
}

/// SSTV mode definition for the UI picker.
class _SstvModeInfo {
  final String name;
  final int visCode;
  final int width;
  final int height;

  const _SstvModeInfo(this.name, this.visCode, this.width, this.height);
}

/// Dialog for selecting an image and SSTV mode for transmission.
///
/// Returns an [SstvSendResult] or null if cancelled.
class SstvSendDialog extends StatefulWidget {
  const SstvSendDialog({super.key});

  @override
  State<SstvSendDialog> createState() => _SstvSendDialogState();
}

class _SstvSendDialogState extends State<SstvSendDialog> {
  static const _modes = [
    _SstvModeInfo('Robot 36', 8, 320, 240),
    _SstvModeInfo('Robot 72', 12, 320, 240),
    _SstvModeInfo('Martin 1', 44, 320, 256),
    _SstvModeInfo('Martin 2', 40, 320, 256),
    _SstvModeInfo('Scottie 1', 60, 320, 256),
    _SstvModeInfo('Scottie 2', 56, 320, 256),
    _SstvModeInfo('Scottie DX', 76, 320, 256),
    _SstvModeInfo('Wraase SC2-180', 55, 320, 256),
    _SstvModeInfo('PD 50', 93, 320, 256),
    _SstvModeInfo('PD 90', 99, 320, 256),
    _SstvModeInfo('PD 120', 95, 640, 496),
    _SstvModeInfo('PD 160', 98, 512, 400),
    _SstvModeInfo('PD 180', 96, 640, 496),
    _SstvModeInfo('PD 240', 97, 640, 496),
    _SstvModeInfo('PD 290', 94, 800, 616),
  ];

  String? _imagePath;
  _SstvModeInfo _selectedMode = _modes[0];
  Uint8List? _imageBytes;

  void _pickImage() async {
    // Use a simple file path input since we don't have file_picker dependency
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Image file path',
                  hintText: '/path/to/image.png',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('CANCEL')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, controller.text),
                      child: const Text('OK')),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!file.existsSync()) return;

    setState(() {
      _imagePath = path;
      _imageBytes = file.readAsBytesSync();
    });
  }

  void _onSend() {
    if (_imagePath == null) return;
    Navigator.pop(
      context,
      SstvSendResult(
        imagePath: _imagePath!,
        modeName: _selectedMode.name,
        width: _selectedMode.width,
        height: _selectedMode.height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SEND SSTV IMAGE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),

              // Mode selector
              Text('MODE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 4),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: DropdownButton<String>(
                  value: _selectedMode.name,
                  underline: const SizedBox(),
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: colors.surfaceContainerHigh,
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  items: _modes
                      .map((m) => DropdownMenuItem(
                          value: m.name,
                          child: Text(
                              '${m.name} (${m.width}x${m.height})')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _selectedMode = _modes.firstWhere((m) => m.name == v);
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Image picker
              Row(children: [
                FilledButton.tonal(
                  onPressed: _pickImage,
                  child: const Text('SELECT IMAGE',
                      style: TextStyle(fontSize: 10, letterSpacing: 1)),
                ),
                const SizedBox(width: 12),
                if (_imagePath != null)
                  Expanded(
                    child: Text(
                      _imagePath!.split('/').last,
                      style: TextStyle(
                          fontSize: 11, color: colors.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              // Image preview
              if (_imageBytes != null)
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                  ),
                ),

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('CANCEL',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              color: colors.onSurfaceVariant))),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: _imagePath != null ? _onSend : null,
                      child: const Text('TRANSMIT',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
