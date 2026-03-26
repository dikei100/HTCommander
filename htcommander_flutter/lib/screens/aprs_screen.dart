import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../handlers/aprs_handler.dart';
import '../widgets/glass_card.dart';
import '../widgets/status_strip.dart';

class AprsScreen extends StatefulWidget {
  const AprsScreen({super.key});

  @override
  State<AprsScreen> createState() => _AprsScreenState();
}

class _AprsScreenState extends State<AprsScreen> {
  final DataBrokerClient _broker = DataBrokerClient();
  bool _showAll = false;
  bool _showWarning = false;
  bool _warningDismissed = false;
  String _selectedRoute = 'WIDE1-1,WIDE2-1';
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  final List<String> _routes = [
    'WIDE1-1,WIDE2-1',
    'WIDE1-1',
    'WIDE2-1',
    'Direct',
  ];

  List<AprsEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _broker.subscribe(1, 'AprsStoreUpdated', _onAprsStoreUpdated);
    _broker.subscribe(DataBroker.allDevices, 'Channels', _onChannelsChanged);
    _broker.subscribe(DataBroker.allDevices, 'State', _onRadioStateChanged);
    // Load initial data
    _loadEntries();
    _checkAprsChannel();
  }

  void _loadEntries() {
    final handler =
        DataBroker.getDataHandlerTyped<AprsHandler>('AprsHandler');
    if (handler != null) {
      setState(() {
        _entries = handler.entries;
      });
    }
  }

  void _onAprsStoreUpdated(int deviceId, String name, Object? data) {
    _loadEntries();
  }

  void _onChannelsChanged(int deviceId, String name, Object? data) {
    if (deviceId < 100) return;
    _checkAprsChannel();
  }

  void _onRadioStateChanged(int deviceId, String name, Object? data) {
    if (deviceId < 100) return;
    _checkAprsChannel();
  }

  void _checkAprsChannel() {
    if (_warningDismissed || !mounted) return;
    // Check if any connected radio has an APRS channel
    bool hasAprs = false;
    for (int id = 100; id < 110; id++) {
      final channels = DataBroker.getValueDynamic(id, 'Channels');
      if (channels is List) {
        for (final ch in channels) {
          if (ch != null && ch is Map && ch['name'] == 'APRS') {
            hasAprs = true;
            break;
          }
        }
      }
      if (hasAprs) break;
    }
    // Also check if any radio is connected
    final state = DataBroker.getValueDynamic(100, 'State');
    final isConnected = state is String && state == 'connected';
    setState(() => _showWarning = isConnected && !hasAprs);
  }

  @override
  void dispose() {
    _broker.dispose();
    _destinationController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  String _formatPosition(AprsEntry entry) {
    final lat = entry.packet.position.coordinateSet.latitude.value;
    final lon = entry.packet.position.coordinateSet.longitude.value;
    if (lat == 0 && lon == 0) return '--';
    final latDir = lat >= 0 ? 'N' : 'S';
    final lonDir = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}$latDir '
        '${lon.abs().toStringAsFixed(4)}$lonDir';
  }

  /// Count unique callsigns (stations) from entries.
  int get _activeStations {
    final seen = <String>{};
    for (final e in _entries) {
      seen.add(e.from);
    }
    return seen.length;
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'position':
      case 'positionMsg':
      case 'positionTime':
      case 'positionTimeMsg':
        return Colors.blue;
      case 'status':
        return Colors.green;
      case 'weatherReport':
        return Colors.orange;
      case 'beacon':
        return Colors.purple;
      case 'message':
        return Colors.teal;
      case 'micE':
      case 'micECurrent':
      case 'micEOld':
        return Colors.indigo;
      case 'object':
      case 'item':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const sectionStyle = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5,
    );
    final isWide = MediaQuery.sizeOf(context).width > 800;

    if (isWide) {
      return Column(
        children: [
          if (_showWarning) _buildWarningBanner(colors),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Left column (flex 3) ---
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        // Frequency monitor panel
                        _buildFrequencyPanel(colors, sectionStyle),
                        const SizedBox(height: 10),
                        // Live APRS Feed
                        Expanded(
                          child: _buildFeedPanel(colors, sectionStyle),
                        ),
                        const SizedBox(height: 10),
                        // Transmit bar
                        _buildTransmitBar(colors),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // --- Right column (flex 2): Map placeholder ---
                  Expanded(
                    flex: 2,
                    child: _buildMapPlaceholder(colors, sectionStyle),
                  ),
                ],
              ),
            ),
          ),
          StatusStrip(
            isConnected: _entries.isNotEmpty,
            encoding: 'AX.25 / APRS',
            extraItems: [
              StatusStripItem(text: '$_activeStations STATIONS'),
              StatusStripItem(text: '${_entries.length} PACKETS'),
            ],
          ),
        ],
      );
    }

    // Mobile: vertical stack
    return Column(
      children: [
        if (_showWarning) _buildWarningBanner(colors),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: _buildFrequencyPanel(colors, sectionStyle),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _buildFeedPanel(colors, sectionStyle),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: _buildTransmitBar(colors),
        ),
        SizedBox(
          height: 200,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: _buildMapPlaceholder(colors, sectionStyle),
          ),
        ),
        StatusStrip(
          isConnected: _entries.isNotEmpty,
          encoding: 'AX.25 / APRS',
          extraItems: [
            StatusStripItem(text: '$_activeStations STATIONS'),
            StatusStripItem(text: '${_entries.length} PACKETS'),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Frequency monitor panel
  // ---------------------------------------------------------------------------
  Widget _buildFrequencyPanel(ColorScheme colors, TextStyle sectionStyle) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FREQUENCY MONITOR',
            style: sectionStyle.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Large frequency display
              Text(
                '144.800',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                  color: colors.primary,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'MHz',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: colors.primary.withAlpha(180),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  'Wide-FM / APRS Standard',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              // PTT Active indicator
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.error.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.error,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'PTT ACTIVE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: colors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Signal metrics row
          Row(
            children: [
              _buildMetric(colors, 'SIGNAL', '-92 dBm'),
              const SizedBox(width: 24),
              _buildMetric(colors, 'SNR', '12.4 dB'),
              const SizedBox(width: 24),
              _buildMetric(colors, 'BANDWIDTH', '12.5 kHz'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(ColorScheme colors, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Live APRS Feed panel
  // ---------------------------------------------------------------------------
  Widget _buildFeedPanel(ColorScheme colors, TextStyle sectionStyle) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'LIVE APRS FEED',
                  style:
                      sectionStyle.copyWith(color: colors.onSurfaceVariant),
                ),
                const Spacer(),
                SizedBox(
                  height: 22,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: Checkbox(
                          value: _showAll,
                          onChanged: (v) =>
                              setState(() => _showAll = v ?? false),
                          visualDensity: const VisualDensity(
                            horizontal: -4,
                            vertical: -4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'SHOW ALL',
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$_activeStations STATIONS ACTIVE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: colors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Divider(
            height: 1,
            thickness: 0.5,
            color: colors.outlineVariant.withAlpha(38),
          ),
          // Table
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowHeight: 32,
                  dataRowMinHeight: 28,
                  dataRowMaxHeight: 32,
                  columnSpacing: 24,
                  horizontalMargin: 16,
                  headingTextStyle: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: colors.onSurfaceVariant,
                  ),
                  dataTextStyle: TextStyle(
                    fontSize: 11,
                    color: colors.onSurface,
                  ),
                  columns: const [
                    DataColumn(label: Text('CALLSIGN')),
                    DataColumn(label: Text('SSID')),
                    DataColumn(label: Text('POSITION')),
                    DataColumn(label: Text('DISTANCE')),
                    DataColumn(label: Text('LAST HEARD')),
                  ],
                  rows: _entries.map((entry) {
                    // Split callsign and SSID
                    final parts = entry.from.split('-');
                    final callsign = parts.isNotEmpty ? parts[0] : entry.from;
                    final ssid = parts.length > 1 ? '-${parts[1]}' : '';

                    final typeColor =
                        _typeColor(entry.packet.dataType.name);

                    return DataRow(cells: [
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: typeColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            callsign,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      )),
                      DataCell(Text(
                        ssid,
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.onSurfaceVariant,
                        ),
                      )),
                      DataCell(Text(
                        _formatPosition(entry),
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      )),
                      DataCell(Text(
                        '--',
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.onSurfaceVariant,
                        ),
                      )),
                      DataCell(Text(_formatTime(entry.time))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Map placeholder (right column)
  // ---------------------------------------------------------------------------
  Widget _buildMapPlaceholder(ColorScheme colors, TextStyle sectionStyle) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: SizedBox.expand(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'STATION MAP',
                  style:
                      sectionStyle.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      size: 64,
                      color: colors.onSurfaceVariant.withAlpha(60),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'APRS MAP',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        color: colors.onSurfaceVariant.withAlpha(80),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Station positions will appear here',
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.onSurfaceVariant.withAlpha(50),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Station counter badge at bottom
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colors.primary.withAlpha(12),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.cell_tower, size: 14, color: colors.primary),
                  const SizedBox(width: 8),
                  Text(
                    '$_activeStations STATIONS TRACKED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: colors.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_entries.length} PACKETS',
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
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Warning banner
  // ---------------------------------------------------------------------------
  Widget _buildWarningBanner(ColorScheme colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: Colors.amber.withAlpha(25),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No APRS channel configured. Set an APRS channel in Settings to enable packet reception.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.amber[700],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => setState(() {
              _showWarning = false;
              _warningDismissed = true;
            }),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Transmit bar
  // ---------------------------------------------------------------------------
  Widget _buildTransmitBar(ColorScheme colors) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // Route dropdown
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ROUTE',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButton<String>(
                  value: _selectedRoute,
                  underline: const SizedBox(),
                  isDense: true,
                  dropdownColor: colors.surfaceContainerHigh,
                  style: TextStyle(fontSize: 10, color: colors.onSurface),
                  items: _routes
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedRoute = v ?? _selectedRoute),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Destination
          SizedBox(
            width: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DESTINATION',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _destinationController,
                    style: TextStyle(fontSize: 11, color: colors.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Callsign',
                      hintStyle:
                          TextStyle(fontSize: 10, color: colors.outline),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
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
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Message
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MESSAGE',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _messageController,
                    style: TextStyle(fontSize: 11, color: colors.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Type APRS message...',
                      hintStyle:
                          TextStyle(fontSize: 10, color: colors.outline),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
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
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              child: const Text('SEND'),
            ),
          ),
        ],
      ),
    );
  }
}
