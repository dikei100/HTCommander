import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';

/// Dialog for audio I/O settings: volume, squelch, mic gain, audio enable.
class RadioAudioDialog extends StatefulWidget {
  final int deviceId;

  const RadioAudioDialog({super.key, required this.deviceId});

  @override
  State<RadioAudioDialog> createState() => _RadioAudioDialogState();
}

class _RadioAudioDialogState extends State<RadioAudioDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  double _volume = 8;
  double _squelch = 0;
  double _outputVolume = 80;
  double _micGain = 80;
  bool _audioEnabled = false;
  bool _recordingEnabled = false;

  @override
  void initState() {
    super.initState();
    _volume = DataBroker.getValue<int>(widget.deviceId, 'Volume', 8).toDouble();
    _squelch =
        DataBroker.getValue<int>(widget.deviceId, 'Squelch', 0).toDouble();
    _outputVolume =
        DataBroker.getValue<int>(0, 'OutputVolume', 80).toDouble();
    _micGain = DataBroker.getValue<int>(0, 'MicGain', 80).toDouble();
    _audioEnabled =
        DataBroker.getValue<int>(widget.deviceId, 'AudioEnabled', 0) == 1;
    _recordingEnabled =
        DataBroker.getValue<int>(0, 'RecordingEnabled', 0) == 1;

    _broker.subscribe(widget.deviceId, 'Volume', _onVolumeChanged);
    _broker.subscribe(widget.deviceId, 'Squelch', _onSquelchChanged);
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _onVolumeChanged(int deviceId, String name, Object? data) {
    if (data is int) setState(() => _volume = data.toDouble());
  }

  void _onSquelchChanged(int deviceId, String name, Object? data) {
    if (data is int) setState(() => _squelch = data.toDouble());
  }

  void _setVolume(double value) {
    setState(() => _volume = value);
    _broker.dispatch(widget.deviceId, 'SetVolume', value.round(),
        store: false);
  }

  void _setSquelch(double value) {
    setState(() => _squelch = value);
    _broker.dispatch(widget.deviceId, 'SetSquelch', value.round(),
        store: false);
  }

  void _setOutputVolume(double value) {
    setState(() => _outputVolume = value);
    DataBroker.dispatch(0, 'OutputVolume', value.round(), store: true);
  }

  void _setMicGain(double value) {
    setState(() => _micGain = value);
    DataBroker.dispatch(0, 'MicGain', value.round(), store: true);
  }

  void _toggleAudio(bool value) {
    setState(() => _audioEnabled = value);
    _broker.dispatch(
        widget.deviceId, 'SetAudio', value ? 1 : 0, store: false);
  }

  void _toggleRecording(bool value) {
    setState(() => _recordingEnabled = value);
    DataBroker.dispatch(0, 'RecordingEnabled', value ? 1 : 0, store: true);
    _broker.dispatch(1, 'SetRecordingEnabled', value, store: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AUDIO SETTINGS',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 20),

              // Audio enable toggle
              Row(children: [
                Switch(value: _audioEnabled, onChanged: _toggleAudio),
                const SizedBox(width: 8),
                Text('Enable Bluetooth Audio',
                    style: TextStyle(fontSize: 11, color: colors.onSurface)),
              ]),
              const SizedBox(height: 12),

              // Volume
              _buildSliderRow('RADIO VOLUME', _volume, 0, 15, _setVolume,
                  colors, _volume.round().toString()),
              const SizedBox(height: 12),

              // Squelch
              _buildSliderRow('SQUELCH', _squelch, 0, 9, _setSquelch, colors,
                  _squelch.round().toString()),
              const SizedBox(height: 12),

              // Output volume
              _buildSliderRow('OUTPUT VOLUME', _outputVolume, 0, 100,
                  _setOutputVolume, colors, '${_outputVolume.round()}%'),
              const SizedBox(height: 12),

              // Mic gain
              _buildSliderRow('MIC GAIN', _micGain, 0, 100, _setMicGain,
                  colors, '${_micGain.round()}%'),
              const SizedBox(height: 16),

              // Recording toggle
              Row(children: [
                Switch(
                    value: _recordingEnabled, onChanged: _toggleRecording),
                const SizedBox(width: 8),
                Text('Record audio',
                    style: TextStyle(fontSize: 11, color: colors.onSurface)),
              ]),
              const SizedBox(height: 20),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('CLOSE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: colors.onSurfaceVariant))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged, ColorScheme colors, String valueText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: colors.onSurfaceVariant)),
          ),
          Text(valueText,
              style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: colors.onSurface)),
        ]),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
