import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/data_broker.dart';

/// Quick frequency entry dialog for VFO.
class QuickFrequencyDialog extends StatefulWidget {
  const QuickFrequencyDialog({super.key});

  @override
  State<QuickFrequencyDialog> createState() => _QuickFrequencyDialogState();
}

class _QuickFrequencyDialogState extends State<QuickFrequencyDialog> {
  late final TextEditingController _freqController;
  String _modulation = 'FM';
  String _bandwidth = 'NARROW';

  @override
  void initState() {
    super.initState();

    // Restore last-used values from DataBroker device 0.
    final lastFreq = DataBroker.getValue<String>(0, 'LastQuickFreq', '');
    final lastMod = DataBroker.getValue<String>(0, 'LastQuickMod', 'FM');
    final lastBw = DataBroker.getValue<String>(0, 'LastQuickBw', 'NARROW');

    _freqController = TextEditingController(text: lastFreq);
    _modulation = lastMod;
    _bandwidth = lastBw;
  }

  @override
  void dispose() {
    _freqController.dispose();
    super.dispose();
  }

  void _onOk() {
    final mhz = double.tryParse(_freqController.text);
    if (mhz == null || mhz <= 0) return;

    final freqHz = (mhz * 1000000).round();
    if (freqHz <= 0 || freqHz > 2147483647) return;

    // Persist last-used values.
    DataBroker.dispatch(0, 'LastQuickFreq', _freqController.text);
    DataBroker.dispatch(0, 'LastQuickMod', _modulation);
    DataBroker.dispatch(0, 'LastQuickBw', _bandwidth);

    Navigator.pop(context, <String, int>{
      'frequency': freqHz,
      'modulation': _modulation == 'AM' ? 1 : 0,
      'bandwidth': _bandwidth == 'WIDE' ? 1 : 0,
    });
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
              Text(
                'QUICK FREQUENCY',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _buildLabel('FREQUENCY (MHZ)', colors),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: TextField(
                  controller: _freqController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  decoration: _inputDecoration(colors),
                ),
              ),
              const SizedBox(height: 12),
              _buildDropdownRow('MODULATION', _modulation, ['FM', 'AM'],
                  (val) {
                setState(() => _modulation = val);
              }, colors),
              const SizedBox(height: 12),
              _buildDropdownRow(
                  'BANDWIDTH', _bandwidth, ['NARROW', 'WIDE'], (val) {
                setState(() => _bandwidth = val);
              }, colors),
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
                    onPressed: _onOk,
                    child: Text(
                      'SET',
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
