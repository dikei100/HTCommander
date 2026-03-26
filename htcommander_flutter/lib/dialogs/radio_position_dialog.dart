import 'package:flutter/material.dart';

/// Dialog for editing a radio's GPS position (latitude, longitude, altitude).
///
/// Returns a Map with 'latitude', 'longitude', 'altitude' as doubles, or null if cancelled.
class RadioPositionDialog extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final double? altitude;

  const RadioPositionDialog({
    super.key,
    this.latitude,
    this.longitude,
    this.altitude,
  });

  @override
  State<RadioPositionDialog> createState() => _RadioPositionDialogState();
}

class _RadioPositionDialogState extends State<RadioPositionDialog> {
  late final TextEditingController _latController;
  late final TextEditingController _lonController;
  late final TextEditingController _altController;

  @override
  void initState() {
    super.initState();
    _latController = TextEditingController(
        text: widget.latitude?.toStringAsFixed(6) ?? '');
    _lonController = TextEditingController(
        text: widget.longitude?.toStringAsFixed(6) ?? '');
    _altController = TextEditingController(
        text: widget.altitude?.toStringAsFixed(0) ?? '');
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _altController.dispose();
    super.dispose();
  }

  void _onSave() {
    final lat = double.tryParse(_latController.text);
    final lon = double.tryParse(_lonController.text);
    if (lat == null || lon == null) return;
    final alt = double.tryParse(_altController.text) ?? 0;
    Navigator.pop(context, {
      'latitude': lat,
      'longitude': lon,
      'altitude': alt,
    });
  }

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
              Text('SET POSITION',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _buildField('LATITUDE', _latController, colors)),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildField('LONGITUDE', _lonController, colors)),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                  width: 160,
                  child:
                      _buildField('ALTITUDE (ft)', _altController, colors)),
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
                      child: const Text('SET',
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
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
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
