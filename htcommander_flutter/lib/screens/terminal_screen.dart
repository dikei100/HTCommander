import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../radio/ax25/ax25_packet.dart';
import '../widgets/glass_card.dart';
import '../widgets/status_strip.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final DataBrokerClient _broker = DataBrokerClient();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isConnected = false;
  bool _isPaused = false;
  final List<_TerminalEntry> _entries = [];
  final List<_TerminalEntry> _pauseBuffer = [];
  List<int> _radioDeviceIds = [];
  int? _selectedRadioId;
  int _rxCount = 0;
  int _txCount = 0;
  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _broker.subscribe(
        DataBroker.allDevices, 'UniqueDataFrame', _onUniqueDataFrame);
    _broker.subscribe(DataBroker.allDevices, 'LockState', _onLockState);
    _broker.subscribe(1, 'ConnectedRadios', _onConnectedRadios);

    _addSystemEntry('Terminal initialized. Awaiting connection.');
  }

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (!_isConnected) return;
    if (data is! AX25Packet) return;
    final packet = data;
    final from =
        packet.addresses.length > 1 ? packet.addresses[1].toString() : '?';
    final dataStr = packet.dataStr ?? '';
    _addEntry(_TerminalEntry(
      timestamp: DateTime.now(),
      tag: 'RX',
      content: '[$from] $dataStr',
    ));
    setState(() {
      _rxCount++;
    });
  }

  void _onLockState(int deviceId, String name, Object? data) {
    if (data == null) {
      if (_selectedRadioId == deviceId && _isConnected) {
        setState(() {
          _isConnected = false;
        });
        _addSystemEntry('Disconnected from Radio $deviceId.');
      }
      return;
    }
    if (data is Map) {
      final usage = data['Usage'] as String? ?? '';
      if (deviceId == _selectedRadioId) {
        final wasConnected = _isConnected;
        setState(() {
          _isConnected = usage == 'Terminal';
        });
        if (_isConnected && !wasConnected) {
          _addSystemEntry('Connected to Radio $deviceId. Terminal active.');
        }
      }
    }
  }

  void _onConnectedRadios(int deviceId, String name, Object? data) {
    if (data is List) {
      final ids = <int>[];
      for (final radio in data) {
        if (radio is Map && radio.containsKey('DeviceId')) {
          ids.add(radio['DeviceId'] as int);
        }
      }
      setState(() {
        _radioDeviceIds = ids;
        if (_selectedRadioId != null && !ids.contains(_selectedRadioId)) {
          _selectedRadioId = null;
        }
      });
    }
  }

  void _addEntry(_TerminalEntry entry) {
    if (_isPaused) {
      _pauseBuffer.add(entry);
    } else {
      setState(() {
        _entries.add(entry);
      });
      _scrollToBottom();
    }
  }

  void _addSystemEntry(String message) {
    _addEntry(_TerminalEntry(
      timestamp: DateTime.now(),
      tag: 'SYS',
      content: message,
    ));
  }

  void _connect() {
    if (_selectedRadioId == null) return;
    _broker.dispatch(_selectedRadioId!, 'SetLock', {
      'Usage': 'Terminal',
      'RegionId': -1,
      'ChannelId': -1,
    });
  }

  void _disconnect() {
    if (_selectedRadioId == null) return;
    _broker.dispatch(_selectedRadioId!, 'SetUnlock', {
      'Usage': 'Terminal',
    });
  }

  void _clearLogs() {
    setState(() {
      _entries.clear();
      _pauseBuffer.clear();
    });
    _addSystemEntry('Terminal cleared.');
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
      if (!_isPaused && _pauseBuffer.isNotEmpty) {
        _entries.addAll(_pauseBuffer);
        _pauseBuffer.clear();
        _scrollToBottom();
      }
    });
  }

  void _exportLogs() {
    // Build export text for clipboard or file
    final buffer = StringBuffer();
    for (final entry in _entries) {
      buffer.writeln(entry.formatted);
    }
    _addSystemEntry('Export: ${_entries.length} lines copied.');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatUptime() {
    final elapsed = DateTime.now().difference(_startTime);
    final h = elapsed.inHours.toString().padLeft(2, '0');
    final m = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _broker.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(colors),
                const SizedBox(height: 12),
                _buildControlRow(colors),
                const SizedBox(height: 12),
                Expanded(child: _buildTerminalArea(colors)),
                const SizedBox(height: 12),
                _buildCommandInput(colors),
              ],
            ),
          ),
        ),
        StatusStrip(
          isConnected: _isConnected,
          encoding: _isConnected ? 'TNC TERMINAL' : 'IDLE',
          extraItems: [
            StatusStripItem(text: 'RX: $_rxCount'),
            StatusStripItem(text: 'TX: $_txCount'),
            StatusStripItem(text: 'UPTIME: ${_formatUptime()}'),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(ColorScheme colors) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SYSTEM TERMINAL',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Direct TNC Interface & Log Stream',
              style: TextStyle(
                fontSize: 11,
                color: colors.outline,
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _isConnected
                ? Colors.green.withAlpha(30)
                : colors.surfaceContainerHighest.withAlpha(80),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _isConnected ? 'CONNECTED' : 'IDLE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: _isConnected
                  ? Colors.green.shade300
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
        const Spacer(),
        // Station selector
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButton<int>(
            value: _selectedRadioId,
            hint: Text(
              'Station',
              style: TextStyle(fontSize: 11, color: colors.outline),
            ),
            underline: const SizedBox(),
            isDense: true,
            dropdownColor: colors.surfaceContainerHigh,
            style: TextStyle(fontSize: 11, color: colors.onSurface),
            items: _radioDeviceIds
                .map((id) =>
                    DropdownMenuItem(value: id, child: Text('Radio $id')))
                .toList(),
            onChanged: (v) => setState(() => _selectedRadioId = v),
          ),
        ),
        const SizedBox(width: 8),
        _buildSmallButton(
          label: _isConnected ? 'Disconnect' : 'Connect',
          colors: colors,
          onPressed: _selectedRadioId != null
              ? (_isConnected ? _disconnect : _connect)
              : null,
          isPrimary: true,
        ),
      ],
    );
  }

  Widget _buildControlRow(ColorScheme colors) {
    return Row(
      children: [
        _buildSmallButton(
          label: 'Clear Logs',
          colors: colors,
          onPressed: _clearLogs,
          icon: Icons.delete_outline,
        ),
        const SizedBox(width: 8),
        _buildSmallButton(
          label: _isPaused ? 'Resume' : 'Pause Output',
          colors: colors,
          onPressed: _togglePause,
          icon: _isPaused ? Icons.play_arrow : Icons.pause,
          isActive: _isPaused,
        ),
        const SizedBox(width: 8),
        _buildSmallButton(
          label: 'Export',
          colors: colors,
          onPressed: _entries.isNotEmpty ? _exportLogs : null,
          icon: Icons.file_download_outlined,
        ),
        if (_isPaused && _pauseBuffer.isNotEmpty) ...[
          const SizedBox(width: 12),
          Text(
            '${_pauseBuffer.length} buffered',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: colors.tertiary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSmallButton({
    required String label,
    required ColorScheme colors,
    VoidCallback? onPressed,
    IconData? icon,
    bool isPrimary = false,
    bool isActive = false,
  }) {
    final enabled = onPressed != null;
    final fgColor = !enabled
        ? colors.onSurfaceVariant.withAlpha(80)
        : isPrimary
            ? colors.primary
            : isActive
                ? colors.tertiary
                : colors.onSurfaceVariant;
    final bgColor = isPrimary
        ? colors.primary.withAlpha(20)
        : isActive
            ? colors.tertiary.withAlpha(20)
            : colors.surfaceContainerHigh;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fgColor),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalArea(ColorScheme colors) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: _entries.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.terminal,
                      size: 28,
                      color: colors.onSurfaceVariant.withAlpha(60),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Terminal ready. Connect a station to begin.',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: colors.onSurfaceVariant.withAlpha(120),
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  return _buildTerminalLine(_entries[index], colors);
                },
              ),
      ),
    );
  }

  Widget _buildTerminalLine(_TerminalEntry entry, ColorScheme colors) {
    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';

    Color tagColor;
    switch (entry.tag) {
      case 'TX':
        tagColor = colors.primary;
      case 'RX':
        tagColor = colors.tertiary;
      case 'SYS':
        tagColor = colors.onSurfaceVariant;
      default:
        tagColor = colors.onSurfaceVariant;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            height: 1.6,
          ),
          children: [
            TextSpan(
              text: timeStr,
              style: TextStyle(color: colors.onSurfaceVariant.withAlpha(140)),
            ),
            TextSpan(
              text: '  [${entry.tag}]',
              style: TextStyle(
                color: tagColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: '  ${entry.content}',
              style: TextStyle(color: colors.onSurface.withAlpha(220)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandInput(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow.withAlpha(160),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(
            '>',
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _inputController,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Enter command...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colors.outline.withAlpha(120),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
              ),
              onSubmitted: _isConnected ? (_) => _transmit() : null,
            ),
          ),
          const SizedBox(width: 8),
          _buildSmallButton(
            label: 'TRANSMIT',
            colors: colors,
            onPressed: _isConnected ? _transmit : null,
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  void _transmit() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _addEntry(_TerminalEntry(
      timestamp: DateTime.now(),
      tag: 'TX',
      content: text,
    ));
    setState(() {
      _txCount++;
      _inputController.clear();
    });
    _scrollToBottom();
  }
}

class _TerminalEntry {
  _TerminalEntry({
    required this.timestamp,
    required this.tag,
    required this.content,
  });

  final DateTime timestamp;
  final String tag;
  final String content;

  String get formatted {
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    return '$timeStr [$tag] $content';
  }
}
