import 'package:flutter/material.dart';

/// Dialog for displaying GPS fix information.
class GpsDetailsDialog extends StatelessWidget {
  final Map<String, String> details;

  const GpsDetailsDialog({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GPS POSITION',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                      letterSpacing: 1, color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              ...details.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  ConstrainedBox(constraints: const BoxConstraints(minWidth: 70, maxWidth: 120), child: Text(e.key,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant))),
                  Expanded(child: SelectableText(e.value,
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace',
                          color: colors.onSurface))),
                ]),
              )),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('CLOSE', style: TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w600, letterSpacing: 1,
                    color: colors.onSurfaceVariant)),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
