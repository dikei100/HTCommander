import 'package:flutter/material.dart';
import '../radio/models/radio_channel_info.dart';
import '../radio/radio_enums.dart';

/// Full channel editor dialog with CTCSS tone selection.
class RadioChannelDialog extends StatefulWidget {
  /// Pass an existing channel for edit mode, or null for create.
  final RadioChannelInfo? channel;

  const RadioChannelDialog({super.key, this.channel});

  @override
  State<RadioChannelDialog> createState() => _RadioChannelDialogState();
}

class _RadioChannelDialogState extends State<RadioChannelDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _rxFreqController;
  late final TextEditingController _txFreqController;

  RadioModulationType _rxMod = RadioModulationType.fm;
  RadioModulationType _txMod = RadioModulationType.fm;
  RadioBandwidthType _bandwidth = RadioBandwidthType.narrow;
  int _powerIndex = 0; // 0=Low, 1=Med, 2=High
  int _rxToneIndex = 0;
  int _txToneIndex = 0;
  bool _scan = false;
  bool _txDisable = false;
  bool _mute = false;
  bool _talkAround = false;

  /// Standard CTCSS tones (Hz).
  static const List<double> _ctcssTones = [
    67.0, 69.3, 71.9, 74.4, 77.0, 79.7, 82.5, 85.4, 88.5, 91.5,
    94.8, 97.4, 100.0, 103.5, 107.2, 110.9, 114.8, 118.8, 123.0, 127.3,
    131.8, 136.5, 141.3, 146.2, 151.4, 156.7, 159.8, 162.2, 165.5, 167.9,
    171.3, 173.8, 177.3, 179.9, 183.5, 186.2, 189.9, 192.8, 196.6, 199.5,
    203.5, 206.5, 210.7, 218.1, 225.7, 229.1, 233.6, 241.8, 250.3, 254.1,
  ];

  static const List<String> _modTypes = ['FM', 'AM', 'DMR'];
  static const List<String> _bwTypes = ['Narrow', 'Wide'];
  static const List<String> _powerLevels = ['Low', 'Medium', 'High'];

  /// Build tone label list: "None" + each tone as "XX.X Hz".
  static List<String> get _toneLabels =>
      ['None', ..._ctcssTones.map((t) => '${t.toStringAsFixed(1)} Hz')];

  @override
  void initState() {
    super.initState();
    final ch = widget.channel;
    _nameController = TextEditingController(text: ch?.nameStr ?? '');
    _rxFreqController = TextEditingController(
        text: ch != null && ch.rxFreq > 0
            ? (ch.rxFreq / 1000000.0).toStringAsFixed(6)
            : '');
    _txFreqController = TextEditingController(
        text: ch != null && ch.txFreq > 0
            ? (ch.txFreq / 1000000.0).toStringAsFixed(6)
            : '');

    if (ch != null) {
      _rxMod = ch.rxMod;
      _txMod = ch.txMod;
      _bandwidth = ch.bandwidth;
      _scan = ch.scan;
      _txDisable = ch.txDisable;
      _mute = ch.mute;
      _talkAround = ch.talkAround;

      if (ch.txAtMaxPower) {
        _powerIndex = 2;
      } else if (ch.txAtMedPower) {
        _powerIndex = 1;
      } else {
        _powerIndex = 0;
      }

      _rxToneIndex = _toneIndexFromValue(ch.rxSubAudio);
      _txToneIndex = _toneIndexFromValue(ch.txSubAudio);
    }
  }

  static int _toneIndexFromValue(int value) {
    if (value == 0) return 0;
    final hz = value / 100.0;
    for (var i = 0; i < _ctcssTones.length; i++) {
      if ((_ctcssTones[i] - hz).abs() < 0.05) return i + 1;
    }
    return 0;
  }

  static int _toneValueFromIndex(int index) {
    if (index <= 0 || index > _ctcssTones.length) return 0;
    return (_ctcssTones[index - 1] * 100).round();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rxFreqController.dispose();
    _txFreqController.dispose();
    super.dispose();
  }

  void _onSave() {
    final rxMhz = double.tryParse(_rxFreqController.text);
    if (rxMhz == null || rxMhz <= 0) return;
    final rxHz = (rxMhz * 1000000).round();
    if (rxHz <= 0 || rxHz > 0x7FFFFFFF) return;

    var txHz = rxHz;
    final txMhz = double.tryParse(_txFreqController.text);
    if (txMhz != null && txMhz > 0) {
      final parsed = (txMhz * 1000000).round();
      if (parsed > 0 && parsed <= 0x7FFFFFFF) txHz = parsed;
    }

    final result = RadioChannelInfo();
    result.channelId = widget.channel?.channelId ?? 0;
    result.nameStr = _nameController.text.trim();
    result.rxFreq = rxHz;
    result.txFreq = txHz;
    result.rxMod = _rxMod;
    result.txMod = _txMod;
    result.bandwidth = _bandwidth;
    result.txAtMaxPower = _powerIndex == 2;
    result.txAtMedPower = _powerIndex == 1;
    result.rxSubAudio = _toneValueFromIndex(_rxToneIndex);
    result.txSubAudio = _toneValueFromIndex(_txToneIndex);
    result.scan = _scan;
    result.txDisable = _txDisable;
    result.mute = _mute;
    result.talkAround = _talkAround;

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEdit = widget.channel != null;
    final toneLabels = _toneLabels;

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit
                      ? 'EDIT CHANNEL ${widget.channel!.channelId}'
                      : 'NEW CHANNEL',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _buildField('NAME', _nameController, colors),
                const SizedBox(height: 12),
                _buildField('RX FREQUENCY (MHz)', _rxFreqController, colors),
                const SizedBox(height: 12),
                _buildField('TX FREQUENCY (MHz)', _txFreqController, colors),
                const SizedBox(height: 12),
                _buildDropdownRow('RX MODULATION', _modTypes[_rxMod.value],
                    _modTypes, (val) {
                  setState(() => _rxMod =
                      RadioModulationType.fromValue(_modTypes.indexOf(val)));
                }, colors),
                const SizedBox(height: 12),
                _buildDropdownRow('TX MODULATION', _modTypes[_txMod.value],
                    _modTypes, (val) {
                  setState(() => _txMod =
                      RadioModulationType.fromValue(_modTypes.indexOf(val)));
                }, colors),
                const SizedBox(height: 12),
                _buildDropdownRow(
                    'BANDWIDTH',
                    _bwTypes[_bandwidth == RadioBandwidthType.wide ? 1 : 0],
                    _bwTypes, (val) {
                  setState(() => _bandwidth = val == 'Wide'
                      ? RadioBandwidthType.wide
                      : RadioBandwidthType.narrow);
                }, colors),
                const SizedBox(height: 12),
                _buildDropdownRow(
                    'POWER', _powerLevels[_powerIndex], _powerLevels, (val) {
                  setState(() => _powerIndex = _powerLevels.indexOf(val));
                }, colors),
                const SizedBox(height: 12),
                _buildDropdownRow(
                    'RX TONE', toneLabels[_rxToneIndex], toneLabels, (val) {
                  setState(() => _rxToneIndex = toneLabels.indexOf(val));
                }, colors),
                const SizedBox(height: 12),
                _buildDropdownRow(
                    'TX TONE', toneLabels[_txToneIndex], toneLabels, (val) {
                  setState(() => _txToneIndex = toneLabels.indexOf(val));
                }, colors),
                const SizedBox(height: 12),
                _buildCheckRow('Scan', _scan, (v) {
                  setState(() => _scan = v);
                }, colors),
                _buildCheckRow('TX Disable', _txDisable, (v) {
                  setState(() => _txDisable = v);
                }, colors),
                _buildCheckRow('Mute', _mute, (v) {
                  setState(() => _mute = v);
                }, colors),
                _buildCheckRow('Talk-Around', _talkAround, (v) {
                  setState(() => _talkAround = v);
                }, colors),
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
                              color: colors.onSurfaceVariant)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _onSave,
                      child: const Text('SAVE',
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
    ColorScheme colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label, colors),
        const SizedBox(height: 4),
        SizedBox(
          height: 32,
          child: TextField(
            controller: controller,
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
        ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 140),
            child: _buildLabel(label, colors)),
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

  Widget _buildCheckRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
    ColorScheme colors,
  ) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(fontSize: 11, color: colors.onSurface)),
        ],
      ),
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
