import 'package:flutter/material.dart';

/// Dialog for adding or editing a contact station.
class StationDialog extends StatefulWidget {
  /// Pass an existing entry map for edit mode, or null for create.
  final Map<String, String>? entry;

  const StationDialog({super.key, this.entry});

  @override
  State<StationDialog> createState() => _StationDialogState();
}

class _StationDialogState extends State<StationDialog> {
  late final TextEditingController _callsignController;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  String _type = 'Amateur';

  static const List<String> _types = [
    'Amateur',
    'Commercial',
    'Emergency',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _callsignController = TextEditingController(text: e?['callsign'] ?? '');
    _nameController = TextEditingController(text: e?['name'] ?? '');
    _descriptionController =
        TextEditingController(text: e?['description'] ?? '');
    _type = e?['type'] ?? 'Amateur';
    if (!_types.contains(_type)) _type = 'Amateur';
  }

  @override
  void dispose() {
    _callsignController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onSave() {
    if (_callsignController.text.isEmpty) return;

    Navigator.pop(context, <String, String>{
      'callsign': _callsignController.text,
      'name': _nameController.text,
      'type': _type,
      'description': _descriptionController.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEdit = widget.entry != null;

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
              Text(
                isEdit ? 'EDIT STATION' : 'NEW STATION',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _buildField('CALLSIGN', _callsignController, colors),
              const SizedBox(height: 12),
              _buildField('NAME', _nameController, colors),
              const SizedBox(height: 12),
              _buildDropdownRow('TYPE', _type, _types, (val) {
                setState(() => _type = val);
              }, colors),
              const SizedBox(height: 12),
              _buildField('DESCRIPTION', _descriptionController, colors,
                  multiline: true),
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
                    onPressed: _onSave,
                    child: Text(
                      'SAVE',
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

  Widget _buildLabel(String text, ColorScheme colors) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
        color: colors.onSurfaceVariant,
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    ColorScheme colors, {
    bool multiline = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label, colors),
        const SizedBox(height: 4),
        SizedBox(
          height: multiline ? null : 32,
          child: TextField(
            controller: controller,
            keyboardType:
                multiline ? TextInputType.multiline : TextInputType.text,
            maxLines: multiline ? 3 : 1,
            style: TextStyle(fontSize: 11, color: colors.onSurface),
            decoration: _inputDecoration(colors),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownRow(
    String label,
    String value,
    List<String> items,
    ValueChanged<String> onChanged,
    ColorScheme colors,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: _buildLabel(label, colors),
        ),
        Expanded(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: DropdownButton<String>(
              value: value,
              underline: const SizedBox(),
              isDense: true,
              isExpanded: true,
              dropdownColor: colors.surfaceContainerHigh,
              style: TextStyle(fontSize: 11, color: colors.onSurface),
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
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
}
