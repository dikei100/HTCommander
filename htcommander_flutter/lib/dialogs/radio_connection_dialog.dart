import 'package:flutter/material.dart';

/// Dialog for listing available/connected Bluetooth radios.
/// Returns a map with 'action' ('connect'/'disconnect') and 'mac'/'name' keys.
class RadioConnectionDialog extends StatefulWidget {
  /// List of device maps with keys: 'name', 'mac', 'state'.
  final List<Map<String, String>> devices;

  const RadioConnectionDialog({super.key, required this.devices});

  @override
  State<RadioConnectionDialog> createState() => _RadioConnectionDialogState();
}

class _RadioConnectionDialogState extends State<RadioConnectionDialog> {
  int _selectedIndex = -1;

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
              Text('RADIO CONNECTION',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (widget.devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No radios found',
                        style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceVariant)),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.devices.length,
                    itemBuilder: (context, index) {
                      final device = widget.devices[index];
                      final name = device['name'] ?? 'Unknown';
                      final mac = device['mac'] ?? '';
                      final state = device['state'] ?? 'Available';
                      final isConnected =
                          state.toLowerCase() == 'connected';
                      final isSelected = _selectedIndex == index;

                      return InkWell(
                        onTap: () => setState(() => _selectedIndex = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.primary.withValues(alpha: 0.15)
                                : null,
                            border: Border(
                              bottom:
                                  BorderSide(color: colors.outlineVariant, width: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isConnected
                                    ? Icons.bluetooth_connected
                                    : Icons.bluetooth,
                                size: 16,
                                color: isConnected
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: colors.onSurface)),
                                    Text(mac,
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontFamily: 'monospace',
                                            color: colors.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isConnected
                                      ? colors.primary.withValues(alpha: 0.2)
                                      : colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(state,
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: isConnected
                                            ? colors.primary
                                            : colors.onSurfaceVariant)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
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
                            color: colors.onSurfaceVariant)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedIndex >= 0 &&
                            (widget.devices[_selectedIndex]['state']
                                        ?.toLowerCase() ==
                                    'connected')
                        ? () => _close('disconnect')
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.error,
                    ),
                    child: const Text('DISCONNECT',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedIndex >= 0 &&
                            (widget.devices[_selectedIndex]['state']
                                        ?.toLowerCase() !=
                                    'connected')
                        ? () => _close('connect')
                        : null,
                    child: const Text('CONNECT',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _close(String action) {
    final device = widget.devices[_selectedIndex];
    Navigator.pop(context, <String, String>{
      'action': action,
      'mac': device['mac'] ?? '',
      'name': device['name'] ?? '',
    });
  }
}
