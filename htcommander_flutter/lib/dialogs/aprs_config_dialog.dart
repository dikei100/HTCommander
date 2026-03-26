import 'package:flutter/material.dart';
import '../core/data_broker.dart';

/// Dialog for configuring APRS settings (callsign, SSID, beacon interval, path).
///
/// Reads/writes settings via DataBroker device 0.
class AprsConfigDialog extends StatefulWidget {
  const AprsConfigDialog({super.key});

  @override
  State<AprsConfigDialog> createState() => _AprsConfigDialogState();
}

class _AprsConfigDialogState extends State<AprsConfigDialog> {
  late final TextEditingController _callsignController;
  late final TextEditingController _ssidController;
  late final TextEditingController _beaconIntervalController;
  late final TextEditingController _commentController;
  bool _beaconEnabled = false;

  @override
  void initState() {
    super.initState();
    _callsignController = TextEditingController(
        text: DataBroker.getValue<String>(0, 'CallSign', ''));
    _ssidController = TextEditingController(
        text: DataBroker.getValue<int>(0, 'StationId', 0).toString());
    _beaconIntervalController = TextEditingController(
        text: DataBroker.getValue<int>(0, 'AprsBeaconInterval', 600)
            .toString());
    _commentController = TextEditingController(
        text: DataBroker.getValue<String>(0, 'AprsComment', ''));
    _beaconEnabled = DataBroker.getValue<int>(0, 'AprsBeaconEnabled', 0) == 1;
  }

  @override
  void dispose() {
    _callsignController.dispose();
    _ssidController.dispose();
    _beaconIntervalController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _onSave() {
    DataBroker.dispatch(0, 'CallSign', _callsignController.text.trim(),
        store: true);
    final ssid = int.tryParse(_ssidController.text) ?? 0;
    DataBroker.dispatch(0, 'StationId', ssid, store: true);
    final interval = int.tryParse(_beaconIntervalController.text) ?? 600;
    DataBroker.dispatch(0, 'AprsBeaconInterval', interval, store: true);
    DataBroker.dispatch(0, 'AprsComment', _commentController.text.trim(),
        store: true);
    DataBroker.dispatch(0, 'AprsBeaconEnabled', _beaconEnabled ? 1 : 0,
        store: true);
    Navigator.pop(context, true);
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
              Text('APRS CONFIGURATION',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child:
                        _buildField('CALLSIGN', _callsignController, colors)),
                const SizedBox(width: 12),
                ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 60, maxWidth: 80),
                    child: _buildField('SSID', _ssidController, colors)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 80, maxWidth: 140),
                    child: _buildField(
                        'BEACON INTERVAL (s)', _beaconIntervalController,
                        colors)),
                const SizedBox(width: 12),
                Row(children: [
                  Checkbox(
                    value: _beaconEnabled,
                    onChanged: (v) =>
                        setState(() => _beaconEnabled = v ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text('Enable beacon',
                      style: TextStyle(fontSize: 11, color: colors.onSurface)),
                ]),
              ]),
              const SizedBox(height: 12),
              _buildField('BEACON COMMENT', _commentController, colors),
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
                      onPressed: _onSave,
                      child: const Text('SAVE',
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

  Widget _buildField(
      String label, TextEditingController controller, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: colors.onSurfaceVariant)),
        const SizedBox(height: 4),
        SizedBox(
          height: 32,
          child: TextField(
            controller: controller,
            style: TextStyle(fontSize: 11, color: colors.onSurface),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.outlineVariant)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.outlineVariant)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.primary)),
              filled: true,
              fillColor: colors.surfaceContainerLow,
            ),
          ),
        ),
      ],
    );
  }
}
