import 'package:flutter/material.dart';

/// Dialog for adding or editing an APRS digipeater route.
///
/// Returns a Map with 'name' and 'path' keys, or null if cancelled.
class AprsRouteDialog extends StatefulWidget {
  final String? initialName;
  final String? initialPath;

  const AprsRouteDialog({super.key, this.initialName, this.initialPath});

  @override
  State<AprsRouteDialog> createState() => _AprsRouteDialogState();
}

class _AprsRouteDialogState extends State<AprsRouteDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _pathController = TextEditingController(text: widget.initialPath ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _onSave() {
    final name = _nameController.text.trim();
    final path = _pathController.text.trim();
    if (name.isEmpty || path.isEmpty) return;
    Navigator.pop(context, {'name': name, 'path': path});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEdit = widget.initialName != null;
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
              Text(isEdit ? 'EDIT ROUTE' : 'ADD ROUTE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              _label('ROUTE NAME', colors),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: TextField(
                  controller: _nameController,
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  decoration: _inputDeco(colors),
                ),
              ),
              const SizedBox(height: 12),
              _label('DIGIPEATER PATH (e.g. WIDE1-1,WIDE2-1)', colors),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: TextField(
                  controller: _pathController,
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  decoration: _inputDeco(colors),
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
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
                      child: Text('SAVE',
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

  Widget _label(String text, ColorScheme colors) => Text(text,
      style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: colors.onSurfaceVariant));

  InputDecoration _inputDeco(ColorScheme colors) => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
      );
}
