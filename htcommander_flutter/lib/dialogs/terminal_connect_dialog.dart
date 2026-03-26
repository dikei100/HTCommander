import 'package:flutter/material.dart';

/// Dialog for selecting which connected radio to use for a terminal session.
/// Returns the selected device ID, or null if cancelled.
class TerminalConnectDialog extends StatefulWidget {
  final List<Map<String, dynamic>> connectedRadios;

  const TerminalConnectDialog({super.key, required this.connectedRadios});

  @override
  State<TerminalConnectDialog> createState() => _TerminalConnectDialogState();
}

class _TerminalConnectDialogState extends State<TerminalConnectDialog> {
  int? _selectedDeviceId;

  @override
  void initState() {
    super.initState();
    if (widget.connectedRadios.isNotEmpty) {
      _selectedDeviceId = widget.connectedRadios[0]['deviceId'] as int?;
    }
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
              Text('TERMINAL CONNECT', style: TextStyle(fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                  color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (widget.connectedRadios.isEmpty)
                Text('No radios connected', style: TextStyle(
                    fontSize: 11, color: colors.onSurfaceVariant))
              else ...[
                Text('SELECT RADIO', style: TextStyle(fontSize: 9,
                    fontWeight: FontWeight.w600, letterSpacing: 1,
                    color: colors.onSurfaceVariant)),
                const SizedBox(height: 4),
                ...widget.connectedRadios.map((r) {
                  final id = r['deviceId'] as int?;
                  final name = r['name'] as String? ?? 'Radio $id';
                  return RadioListTile<int?>(
                    title: Text(name, style: TextStyle(fontSize: 11,
                        color: colors.onSurface)),
                    value: id,
                    groupValue: _selectedDeviceId,
                    onChanged: (v) => setState(() => _selectedDeviceId = v),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  );
                }),
              ],
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context),
                    child: Text('CANCEL', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1,
                        color: colors.onSurfaceVariant))),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _selectedDeviceId != null
                        ? () => Navigator.pop(context, _selectedDeviceId)
                        : null,
                    child: const Text('CONNECT', style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        letterSpacing: 1))),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
