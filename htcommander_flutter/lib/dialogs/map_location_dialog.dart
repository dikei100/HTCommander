/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

/// Dialog for entering or editing a map location.
class MapLocationDialog extends StatefulWidget {
  final String? initialLatitude;
  final String? initialLongitude;
  final String? initialName;

  const MapLocationDialog({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialName,
  });

  @override
  State<MapLocationDialog> createState() => _MapLocationDialogState();
}

class _MapLocationDialogState extends State<MapLocationDialog> {
  late final TextEditingController _latController;
  late final TextEditingController _lonController;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _latController = TextEditingController(text: widget.initialLatitude ?? '');
    _lonController = TextEditingController(text: widget.initialLongitude ?? '');
    _nameController = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onOk() {
    if (_latController.text.trim().isEmpty ||
        _lonController.text.trim().isEmpty) {
      return;
    }

    Navigator.pop(context, <String, dynamic>{
      'latitude': _latController.text.trim(),
      'longitude': _lonController.text.trim(),
      'name': _nameController.text.trim(),
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
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MAP LOCATION',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'LATITUDE',
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
                  controller: _latController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: true),
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  decoration: _inputDecoration(colors),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'LONGITUDE',
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
                  controller: _lonController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: true),
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  decoration: _inputDecoration(colors),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'LOCATION NAME',
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
                  controller: _nameController,
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  decoration: _inputDecoration(colors),
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
