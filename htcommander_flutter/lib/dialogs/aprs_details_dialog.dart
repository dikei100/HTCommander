import 'package:flutter/material.dart';
import '../handlers/aprs_handler.dart';
import '../radio/aprs/packet_data_type.dart';

/// Dialog for displaying detailed information about an APRS packet.
class AprsDetailsDialog extends StatelessWidget {
  final AprsEntry entry;

  const AprsDetailsDialog({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final aprs = entry.packet;

    final fields = <String, String>{};
    fields['From'] = entry.from;
    fields['To'] = entry.to;
    fields['Time'] = _formatTime(entry.time);
    fields['Direction'] = entry.incoming ? 'Received' : 'Sent';
    fields['Data Type'] = aprs.dataType.name;

    if (aprs.position.isValid) {
      fields['Latitude'] =
          aprs.position.coordinateSet.latitude.value.toStringAsFixed(6);
      fields['Longitude'] =
          aprs.position.coordinateSet.longitude.value.toStringAsFixed(6);
      if (aprs.position.altitude != 0) {
        fields['Altitude'] = '${aprs.position.altitude.toStringAsFixed(0)} ft';
      }
    }

    if (aprs.dataType == PacketDataType.message) {
      fields['Addressee'] = aprs.messageData.addressee;
      fields['Message'] = aprs.messageData.msgText;
      if (aprs.messageData.seqId.isNotEmpty) {
        fields['Sequence ID'] = aprs.messageData.seqId;
      }
      fields['Message Type'] = aprs.messageData.msgType.name;
    }

    if (aprs.comment.isNotEmpty) {
      fields['Comment'] = aprs.comment;
    }

    if (aprs.rawPacket.isNotEmpty) {
      fields['Raw'] = aprs.rawPacket;
    }

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('APRS PACKET DETAILS',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              ...fields.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
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
