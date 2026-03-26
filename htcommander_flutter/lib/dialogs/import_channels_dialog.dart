import 'package:flutter/material.dart';
import '../radio/models/radio_channel_info.dart';

/// Dialog for previewing and importing channels from a file.
/// Returns the list of channels if accepted, or null if cancelled.
class ImportChannelsDialog extends StatelessWidget {
  final List<RadioChannelInfo> channels;

  const ImportChannelsDialog({super.key, required this.channels});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('IMPORT CHANNELS', style: TextStyle(fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 1,
                color: colors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('${channels.length} channels found', style: TextStyle(
                fontSize: 11, color: colors.onSurfaceVariant)),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(child: DataTable(
                headingRowHeight: 28, dataRowMinHeight: 24, dataRowMaxHeight: 28,
                columnSpacing: 12, horizontalMargin: 8,
                headingTextStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    letterSpacing: 1, color: colors.onSurfaceVariant),
                dataTextStyle: TextStyle(fontSize: 10, color: colors.onSurface),
                columns: const [
                  DataColumn(label: Text('ID'), numeric: true),
                  DataColumn(label: Text('NAME')),
                  DataColumn(label: Text('RX FREQ'), numeric: true),
                  DataColumn(label: Text('TX FREQ'), numeric: true),
                  DataColumn(label: Text('MODE')),
                  DataColumn(label: Text('BW')),
                ],
                rows: channels.map((c) => DataRow(cells: [
                  DataCell(Text('${c.channelId}')),
                  DataCell(Text(c.nameStr)),
                  DataCell(Text(_formatFreq(c.rxFreq))),
                  DataCell(Text(_formatFreq(c.txFreq))),
                  DataCell(Text(c.rxMod.name.toUpperCase())),
                  DataCell(Text(c.bandwidth.name.toUpperCase())),
                ])).toList(),
              )),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context),
                  child: Text('CANCEL', style: TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w600, letterSpacing: 1,
                      color: colors.onSurfaceVariant))),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: () => Navigator.pop(context, channels),
                  child: const Text('IMPORT ALL', style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      letterSpacing: 1))),
            ]),
          ]),
        ),
      ),
    );
  }

  String _formatFreq(int hz) => (hz / 1000000).toStringAsFixed(4);
}
