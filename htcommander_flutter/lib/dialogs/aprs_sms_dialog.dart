import 'package:flutter/material.dart';

/// Dialog for composing and sending an APRS message.
///
/// Returns a Map with 'destination' and 'message' keys, or null if cancelled.
class AprsSmsDialog extends StatefulWidget {
  final String? initialDestination;

  const AprsSmsDialog({super.key, this.initialDestination});

  @override
  State<AprsSmsDialog> createState() => _AprsSmsDialogState();
}

class _AprsSmsDialogState extends State<AprsSmsDialog> {
  late final TextEditingController _destController;
  late final TextEditingController _msgController;

  @override
  void initState() {
    super.initState();
    _destController =
        TextEditingController(text: widget.initialDestination ?? '');
    _msgController = TextEditingController();
  }

  @override
  void dispose() {
    _destController.dispose();
    _msgController.dispose();
    super.dispose();
  }

  void _onSend() {
    final dest = _destController.text.trim();
    final msg = _msgController.text.trim();
    if (dest.isEmpty || msg.isEmpty) return;
    Navigator.pop(context, {'destination': dest, 'message': msg});
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
              Text('SEND APRS MESSAGE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              _label('DESTINATION CALLSIGN', colors),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: TextField(
                  controller: _destController,
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  decoration: _inputDeco(colors),
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(height: 12),
              _label('MESSAGE', colors),
              const SizedBox(height: 4),
              TextField(
                controller: _msgController,
                maxLines: 3,
                style: TextStyle(fontSize: 11, color: colors.onSurface),
                decoration: _inputDeco(colors),
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
                      onPressed: _onSend,
                      child: const Text('SEND',
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
