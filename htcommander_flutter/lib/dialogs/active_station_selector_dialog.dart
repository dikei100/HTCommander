/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

/// Dialog for selecting an active station from a list of callsigns.
class ActiveStationSelectorDialog extends StatefulWidget {
  final List<String> stations;

  const ActiveStationSelectorDialog({super.key, required this.stations});

  @override
  State<ActiveStationSelectorDialog> createState() =>
      _ActiveStationSelectorDialogState();
}

class _ActiveStationSelectorDialogState
    extends State<ActiveStationSelectorDialog> {
  int _selectedIndex = -1;

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
                'SELECT STATION',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: RadioGroup<int>(
                  groupValue: _selectedIndex,
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedIndex = v);
                  },
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.stations.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: Radio<int>(value: index),
                        title: Text(
                          widget.stations[index],
                          style:
                              TextStyle(fontSize: 11, color: colors.onSurface),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onTap: () => setState(() => _selectedIndex = index),
                      );
                    },
                  ),
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
                    onPressed: _selectedIndex >= 0
                        ? () => Navigator.pop(
                            context, widget.stations[_selectedIndex])
                        : null,
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
