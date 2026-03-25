/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dialog for editing station identification settings.
class EditIdentSettingsDialog extends StatefulWidget {
  final String initialText;
  final int initialInterval;
  final bool initialEnabled;

  const EditIdentSettingsDialog({
    super.key,
    required this.initialText,
    required this.initialInterval,
    required this.initialEnabled,
  });

  @override
  State<EditIdentSettingsDialog> createState() =>
      _EditIdentSettingsDialogState();
}

class _EditIdentSettingsDialogState extends State<EditIdentSettingsDialog> {
  late final TextEditingController _textController;
  late final TextEditingController _intervalController;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _intervalController =
        TextEditingController(text: widget.initialInterval.toString());
    _enabled = widget.initialEnabled;
  }

  @override
  void dispose() {
    _textController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  void _onOk() {
    if (_textController.text.trim().isEmpty) return;
    final interval = int.tryParse(_intervalController.text);
    if (interval == null || interval <= 0) return;

    Navigator.pop(context, <String, dynamic>{
      'text': _textController.text.trim(),
      'interval': interval,
      'enabled': _enabled,
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
                'IDENTIFICATION SETTINGS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'IDENTIFICATION TEXT',
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
                  controller: _textController,
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  decoration: _inputDecoration(colors),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'INTERVAL (SECONDS)',
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
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  decoration: _inputDecoration(colors),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Enabled',
                    style: TextStyle(fontSize: 11, color: colors.onSurface),
                  ),
                ],
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
