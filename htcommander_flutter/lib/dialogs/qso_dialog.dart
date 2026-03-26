import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/data_broker.dart';

/// Dialog for adding or editing a QSO logbook entry.
class QsoDialog extends StatefulWidget {
  /// Pass an existing entry map for edit mode, or null for create.
  final Map<String, String>? entry;

  const QsoDialog({super.key, this.entry});

  @override
  State<QsoDialog> createState() => _QsoDialogState();
}

class _QsoDialogState extends State<QsoDialog> {
  late final TextEditingController _callsignController;
  late final TextEditingController _freqController;
  late final TextEditingController _rstSentController;
  late final TextEditingController _rstRecvController;
  late final TextEditingController _myCallsignController;
  late final TextEditingController _notesController;

  String _mode = 'FM';
  late String _dateTime;

  static const List<String> _modes = [
    'FM',
    'AM',
    'SSB',
    'CW',
    'RTTY',
    'FT8',
    'FT4',
    'DIGITAL',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.entry;

    _dateTime = e?['dateTime'] ?? _utcNow();
    _callsignController = TextEditingController(text: e?['callsign'] ?? '');
    _freqController = TextEditingController(text: e?['frequency'] ?? '');
    _rstSentController = TextEditingController(text: e?['rstSent'] ?? '59');
    _rstRecvController =
        TextEditingController(text: e?['rstReceived'] ?? '59');
    _myCallsignController = TextEditingController(
      text: e?['myCallsign'] ??
          DataBroker.getValue<String>(0, 'CallSign', ''),
    );
    _notesController = TextEditingController(text: e?['notes'] ?? '');
    _mode = e?['mode'] ?? 'FM';
    if (!_modes.contains(_mode)) _mode = 'FM';
  }

  @override
  void dispose() {
    _callsignController.dispose();
    _freqController.dispose();
    _rstSentController.dispose();
    _rstRecvController.dispose();
    _myCallsignController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static String _utcNow() {
    final now = DateTime.now().toUtc();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}Z';
  }

  String _computeBand() {
    final mhz = double.tryParse(_freqController.text);
    if (mhz == null || mhz <= 0) return '';
    if (mhz < 0.5) return '2200m';
    if (mhz < 2) return '630m';
    if (mhz < 4) return '160m';
    if (mhz < 8) return '80m';
    if (mhz < 11) return '40m';
    if (mhz < 15) return '30m';
    if (mhz < 22) return '20m';
    if (mhz < 24) return '17m';
    if (mhz < 25) return '15m';
    if (mhz < 28) return '12m';
    if (mhz < 30) return '10m';
    if (mhz < 76) return '6m';
    if (mhz < 150) return '2m';
    if (mhz < 450) return '70cm';
    if (mhz < 930) return '33cm';
    if (mhz < 1500) return '23cm';
    return '';
  }

  void _onSave() {
    if (_callsignController.text.isEmpty) return;

    Navigator.pop(context, <String, String>{
      'dateTime': _dateTime,
      'callsign': _callsignController.text,
      'frequency': _freqController.text,
      'mode': _mode,
      'band': _computeBand(),
      'rstSent': _rstSentController.text,
      'rstReceived': _rstRecvController.text,
      'myCallsign': _myCallsignController.text,
      'notes': _notesController.text,
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
        constraints: BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'EDIT QSO' : 'NEW QSO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _buildReadOnlyField('DATE / TIME (UTC)', _dateTime, colors),
                const SizedBox(height: 12),
                _buildField('CALLSIGN', _callsignController, colors),
                const SizedBox(height: 12),
                _buildField('FREQUENCY (MHZ)', _freqController, colors,
                    numeric: true),
                const SizedBox(height: 12),
                _buildDropdownRow('MODE', _mode, _modes, (val) {
                  setState(() => _mode = val);
                }, colors),
                const SizedBox(height: 12),
                _buildReadOnlyField('BAND', _computeBand(), colors),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                          'RST SENT', _rstSentController, colors),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildField(
                          'RST RECEIVED', _rstRecvController, colors),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildField(
                    'MY CALLSIGN', _myCallsignController, colors),
                const SizedBox(height: 12),
                _buildField('NOTES', _notesController, colors,
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
    bool numeric = false,
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
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : (multiline ? TextInputType.multiline : TextInputType.text),
            inputFormatters: numeric
                ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
                : null,
            maxLines: multiline ? 3 : 1,
            style: TextStyle(fontSize: 11, color: colors.onSurface),
            decoration: _inputDecoration(colors),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(
      String label, String value, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label, colors),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow.withAlpha(128),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.outlineVariant.withAlpha(77)),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurface.withAlpha(179),
            ),
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
