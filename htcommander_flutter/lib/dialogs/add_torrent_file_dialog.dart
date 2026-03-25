/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

/// Dialog for adding a torrent file entry.
class AddTorrentFileDialog extends StatefulWidget {
  final Future<String?> Function()? onBrowse;

  const AddTorrentFileDialog({super.key, this.onBrowse});

  @override
  State<AddTorrentFileDialog> createState() => _AddTorrentFileDialogState();
}

class _AddTorrentFileDialogState extends State<AddTorrentFileDialog> {
  late final TextEditingController _filenameController;
  late final TextEditingController _descriptionController;
  int _modeIndex = 0;

  @override
  void initState() {
    super.initState();
    _filenameController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _filenameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _onBrowse() async {
    final result = await widget.onBrowse?.call();
    if (result != null) {
      _filenameController.text = result;
    }
  }

  void _onOk() {
    if (_filenameController.text.trim().isEmpty) return;

    Navigator.pop(context, <String, dynamic>{
      'filename': _filenameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'mode': _modeIndex,
    });
  }

  InputDecoration _inputDecoration(ColorScheme colors) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: colors.primary),
      ),
      filled: true,
      fillColor: colors.surfaceContainerLow,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final modes = ['Request', 'Provide'];

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ADD TORRENT FILE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'FILENAME',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _filenameController,
                        style:
                            TextStyle(fontSize: 11, color: colors.onSurface),
                        decoration: _inputDecoration(colors),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: TextButton(
                      onPressed: _onBrowse,
                      child: Text(
                        'BROWSE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'DESCRIPTION',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: TextField(
                  controller: _descriptionController,
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  decoration: _inputDecoration(colors),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'MODE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: DropdownButton<int>(
                  value: _modeIndex,
                  underline: const SizedBox(),
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: colors.surfaceContainerHigh,
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  items: modes.asMap().entries.map((e) {
                    return DropdownMenuItem(value: e.key, child: Text(e.value));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _modeIndex = v);
                  },
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'CANCEL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _onOk,
                    child: Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
