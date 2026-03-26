import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../handlers/packet_store.dart';
import '../radio/ax25/ax25_packet.dart';

/// Dialog for displaying a hex dump of packet data.
class PacketCaptureViewerDialog extends StatelessWidget {
  final AX25Packet packet;

  const PacketCaptureViewerDialog({super.key, required this.packet});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final fields = <String, String>{};
    fields['Time'] = _formatTime(packet.time);
    fields['Direction'] = packet.incoming ? 'Received' : 'Sent';
    if (packet.addresses.length > 1) {
      fields['Source'] = packet.addresses[1].toString();
    }
    if (packet.addresses.isNotEmpty) {
      fields['Destination'] = packet.addresses[0].toString();
    }
    fields['Channel'] = packet.channelName;
    final packetData = packet.data;
    fields['Data Length'] = '${packetData?.length ?? 0} bytes';

    final hexDump = (packetData != null && packetData.isNotEmpty)
        ? PacketStore.hexDump(packetData)
        : '(empty)';

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PACKET CAPTURE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              ...fields.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(e.key,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurfaceVariant)),
                        ),
                        Expanded(
                          child: SelectableText(e.value,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: colors.onSurface)),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 12),
              Text('HEX DUMP',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    hexDump,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: colors.onSurface,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
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

  String _formatTime(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
