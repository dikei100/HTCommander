import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../handlers/log_store.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  bool _showBtFrames = false;
  bool _showLoopback = false;
  final ScrollController _scrollController = ScrollController();
  late final DataBrokerClient _broker;
  List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _broker = DataBrokerClient();

    // Subscribe to live log events
    _broker.subscribe(1, 'LogInfo', _onLogInfo);
    _broker.subscribe(1, 'LogError', _onLogError);

    // Load existing entries from LogStore if registered
    final logStore = DataBroker.getDataHandlerTyped<LogStore>('LogStore');
    if (logStore != null) {
      _logLines = logStore.entries
          .map((e) => '[${_formatTime(e.time)}] ${e.level}: ${e.message}')
          .toList();
    }
  }

  @override
  void dispose() {
    _broker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogInfo(int deviceId, String name, Object? data) {
    if (!mounted || data is! String) return;
    setState(() {
      _logLines.add('[${_formatTime(DateTime.now())}] Info: $data');
    });
    _scrollToBottom();
  }

  void _onLogError(int deviceId, String name, Object? data) {
    if (!mounted || data is! String) return;
    setState(() {
      _logLines.add('[${_formatTime(DateTime.now())}] Error: $data');
    });
    _scrollToBottom();
  }

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildHeader(colors),
        Expanded(
          child: _buildLogArea(colors),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme colors) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: colors.surfaceContainer,
      child: Row(
        children: [
          Text(
            'DEBUG CONSOLE',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colors.onSurface,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 28,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _showBtFrames,
                  onChanged: (v) {
                    final val = v ?? false;
                    setState(() => _showBtFrames = val);
                    _broker.dispatch(0, 'BluetoothFramesDebug', val ? 1 : 0);
                  },
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                ),
                Text(
                  'BT FRAMES',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 28,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _showLoopback,
                  onChanged: (v) {
                    final val = v ?? false;
                    setState(() => _showLoopback = val);
                    _broker.dispatch(1, 'LoopbackMode', val ? 1 : 0);
                  },
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                ),
                Text(
                  'LOOPBACK',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _logLines.clear());
              // Also clear the LogStore if available
              final logStore =
                  DataBroker.getDataHandlerTyped<LogStore>('LogStore');
              logStore?.clearLogs();
            },
            icon: const Icon(Icons.delete_outline, size: 14),
            label: const Text('CLEAR'),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              textStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.save_outlined, size: 14),
            label: const Text('SAVE'),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              textStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogArea(ColorScheme colors) {
    final logText = _logLines.join('\n');

    return Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.outlineVariant.withAlpha(60),
        ),
      ),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            logText.isEmpty ? 'No log entries yet.' : logText,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: colors.onSurface,
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}
