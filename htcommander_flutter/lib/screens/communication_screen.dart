import 'package:flutter/material.dart';
import '../core/data_broker_client.dart';
import '../radio/models/radio_dev_info.dart';
import '../radio/models/radio_ht_status.dart';
import '../radio/models/radio_settings.dart';
import '../radio/models/radio_channel_info.dart';
import '../radio/models/radio_position.dart';
import '../widgets/glass_card.dart';
import '../widgets/vfo_display.dart';
import '../widgets/signal_bars.dart';
import '../widgets/radio_status_card.dart';
import '../widgets/ptt_button.dart';

/// Communication Hub — the flagship screen.
/// Layout: Radio panel (left) + two-column content (right).
class CommunicationScreen extends StatefulWidget {
  const CommunicationScreen({super.key});

  @override
  State<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends State<CommunicationScreen> {
  final TextEditingController _inputController = TextEditingController();
  String _selectedMode = 'Chat';
  bool _isMuted = false;

  // DataBroker wiring
  late final DataBrokerClient _broker;

  // Live state from DataBroker
  bool _isConnected = false;
  String? _deviceName;
  int _rssi = 0;
  bool _isTransmitting = false;
  int _batteryPercent = 0;
  bool _isGpsLocked = false;
  double _vfoAFreq = 0;
  double _vfoBFreq = 0;
  String _vfoAName = '';
  String _vfoBName = '';
  final List<String> _messages = [];

  // Cached radio data for deriving VFO info
  RadioSettings? _settings;
  List<RadioChannelInfo?> _channels = [];

  @override
  void initState() {
    super.initState();
    _broker = DataBrokerClient();

    // Load current state from DataBroker (screen may be rebuilt on tab switch)
    _loadCurrentState();

    _broker.subscribe(100, 'State', _onState);
    _broker.subscribe(100, 'Info', _onInfo);
    _broker.subscribe(100, 'FriendlyName', _onFriendlyName);
    _broker.subscribe(100, 'HtStatus', _onHtStatus);
    _broker.subscribe(100, 'Settings', _onSettings);
    _broker.subscribe(100, 'Channels', _onChannels);
    _broker.subscribe(100, 'BatteryAsPercentage', _onBattery);
    _broker.subscribe(100, 'Position', _onPosition);
  }

  void _loadCurrentState() {
    final state = _broker.getValue<String>(100, 'State', '');
    _isConnected = state.toLowerCase() == 'connected';

    final friendlyName = _broker.getValue<String>(100, 'FriendlyName', '');
    if (friendlyName.isNotEmpty) {
      _deviceName = friendlyName;
    } else {
      final info = _broker.getValueDynamic(100, 'Info');
      if (info is RadioDevInfo) {
        _deviceName = 'Radio ${info.productId}';
      }
    }

    final htStatus = _broker.getValueDynamic(100, 'HtStatus');
    if (htStatus is RadioHtStatus) {
      _rssi = htStatus.rssi;
      _isTransmitting = htStatus.isInTx;
    }

    final settings = _broker.getValueDynamic(100, 'Settings');
    if (settings is RadioSettings) {
      _settings = settings;
    }

    final channels = _broker.getValueDynamic(100, 'Channels');
    if (channels is List) {
      _channels = channels.cast<RadioChannelInfo?>();
    }

    _batteryPercent = _broker.getValue<int>(100, 'BatteryAsPercentage', 0);

    final pos = _broker.getValueDynamic(100, 'Position');
    if (pos is RadioPosition) {
      _isGpsLocked = pos.isGpsLocked;
    }

    _updateVfoFromChannels();
  }

  @override
  void dispose() {
    _broker.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _onState(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _isConnected = (data is String && data.toLowerCase() == 'connected');
    });
  }

  void _onInfo(int deviceId, String name, Object? data) {
    if (!mounted || data is! RadioDevInfo) return;
    // Only set from Info if we don't already have a friendly name
    if (_deviceName == null || _deviceName!.startsWith('Radio ')) {
      setState(() => _deviceName = 'Radio ${data.productId}');
    }
  }

  void _onFriendlyName(int deviceId, String name, Object? data) {
    if (!mounted || data is! String || data.isEmpty) return;
    setState(() => _deviceName = data);
  }

  void _onHtStatus(int deviceId, String name, Object? data) {
    if (!mounted || data is! RadioHtStatus) return;
    setState(() {
      _rssi = data.rssi;
      _isTransmitting = data.isInTx;
    });
  }

  void _onSettings(int deviceId, String name, Object? data) {
    if (!mounted || data is! RadioSettings) return;
    setState(() {
      _settings = data;
      _updateVfoFromChannels();
    });
  }

  void _onChannels(int deviceId, String name, Object? data) {
    if (!mounted || data is! List) return;
    setState(() {
      _channels = data.cast<RadioChannelInfo?>();
      _updateVfoFromChannels();
    });
  }

  void _onBattery(int deviceId, String name, Object? data) {
    if (!mounted || data is! int) return;
    setState(() {
      _batteryPercent = data;
    });
  }

  void _onPosition(int deviceId, String name, Object? data) {
    if (!mounted || data is! RadioPosition) return;
    setState(() {
      _isGpsLocked = data.isGpsLocked;
    });
  }

  void _updateVfoFromChannels() {
    final settings = _settings;
    if (settings == null) return;

    final chA = settings.channelA;
    final chB = settings.channelB;

    if (chA >= 0 && chA < _channels.length && _channels[chA] != null) {
      final ch = _channels[chA]!;
      _vfoAFreq = ch.rxFreq / 1000000.0;
      _vfoAName = ch.nameStr;
    } else {
      _vfoAFreq = 0;
      _vfoAName = '';
    }

    if (chB >= 0 && chB < _channels.length && _channels[chB] != null) {
      final ch = _channels[chB]!;
      _vfoBFreq = ch.rxFreq / 1000000.0;
      _vfoBName = ch.nameStr;
    } else {
      _vfoBFreq = 0;
      _vfoBName = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Header bar
        _buildHeader(colors),
        // Main content
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Radio panel (left side)
              SizedBox(
                width: 280,
                child: _buildRadioPanel(colors),
              ),
              // Content area (right side, two columns)
              Expanded(
                child: _buildContentArea(colors),
              ),
            ],
          ),
        ),
        // Bottom input bar
        _buildInputBar(colors),
      ],
    );
  }

  Widget _buildHeader(ColorScheme colors) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: colors.surfaceContainer,
      child: Row(
        children: [
          Text(
            'Communication',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _isConnected ? 'Connected' : 'Idle',
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // Send SSTV button
          _HeaderButton(
            label: 'Send SSTV',
            onPressed: _isConnected ? () {} : null,
          ),
          const SizedBox(width: 6),
          // Mute toggle
          _HeaderToggle(
            label: 'Mute',
            isActive: _isMuted,
            onPressed: () => setState(() => _isMuted = !_isMuted),
          ),
          const SizedBox(width: 6),
          // Mode selector
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<String>(
              value: _selectedMode,
              underline: const SizedBox(),
              isDense: true,
              dropdownColor: colors.surfaceContainerHigh,
              style: TextStyle(fontSize: 11, color: colors.onSurface),
              items: ['Chat', 'Speak', 'Morse', 'DTMF']
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedMode = v!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioPanel(ColorScheme colors) {
    return Container(
      color: colors.surfaceContainerLow,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Radio status card
            RadioStatusCard(
              deviceName: _deviceName,
              isConnected: _isConnected,
              rssi: _rssi,
              isTransmitting: _isTransmitting,
              batteryPercent: _batteryPercent,
              isGpsLocked: _isGpsLocked,
            ),
            const SizedBox(height: 12),

            // VFO A
            VfoDisplay(
              label: 'VFO A',
              frequency: _vfoAFreq,
              channelName: _vfoAName,
              isActive: true,
              isPrimary: true,
            ),
            const SizedBox(height: 8),

            // VFO B
            VfoDisplay(
              label: 'VFO B',
              frequency: _vfoBFreq,
              channelName: _vfoBName,
              isActive: false,
              isPrimary: false,
            ),
            const SizedBox(height: 16),

            // PTT Button
            Center(
              child: PttButton(
                isEnabled: _isConnected,
                isTransmitting: _isTransmitting,
                size: 72,
                onPttStart: _onPttStart,
                onPttStop: _onPttStop,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isTransmitting ? 'TRANSMITTING' : 'PRESS TO TALK',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: _isTransmitting ? colors.error : colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // RSSI / TX bars
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _MiniStatus(
                    label: 'RSSI',
                    child: SignalBars(level: _rssi, height: 14),
                  ),
                  const SizedBox(width: 16),
                  _MiniStatus(
                    label: 'TX',
                    child: SignalBars(
                      level: _isTransmitting ? 12 : 0,
                      isTransmitting: true,
                      height: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onPttStart() {
    // Placeholder — will dispatch TransmitVoicePCM when audio pipeline is ready
    _broker.dispatch(100, 'TransmitVoicePCM', null, store: false);
  }

  void _onPttStop() {
    // No-op for now — PTT release handled by audio pipeline
  }

  Widget _buildContentArea(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: Local Packet Node / SSTV
          Expanded(
            child: _buildPacketNodeCard(colors),
          ),
          const SizedBox(width: 14),
          // Right column: Operation log
          Expanded(
            child: _buildOperationLog(colors),
          ),
        ],
      ),
    );
  }

  Widget _buildPacketNodeCard(ColorScheme colors) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LOCAL PACKET NODE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          // SSTV / Data Link placeholder
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SSTV / DATA LINK',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Waiting for incoming data...',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Status / Protocol row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STATUS',
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Standby',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROTOCOL',
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'AX.25',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOperationLog(ColorScheme colors) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OPERATION',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.outline,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _messages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _messages[index],
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurface,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: colors.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              style: TextStyle(fontSize: 12, color: colors.onSurface),
              decoration: InputDecoration(
                hintText: 'Type message...',
                hintStyle: TextStyle(fontSize: 12, color: colors.outline),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              ),
              onSubmitted: _isConnected ? (_) => _sendMessage() : null,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _isConnected ? _sendMessage : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Transmit'),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: _isConnected ? () {} : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    // Dispatch chat message via DataBroker
    _broker.dispatch(1, 'Chat', text, store: false);
    setState(() {
      _messages.add(text);
      _inputController.clear();
    });
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text(label),
    );
  }
}

class _HeaderToggle extends StatelessWidget {
  const _HeaderToggle({
    required this.label,
    required this.isActive,
    this.onPressed,
  });
  final String label;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        backgroundColor: isActive ? colors.primaryContainer : null,
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text(label),
    );
  }
}

class _MiniStatus extends StatelessWidget {
  const _MiniStatus({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
