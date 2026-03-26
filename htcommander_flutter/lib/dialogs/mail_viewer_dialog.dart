import 'package:flutter/material.dart';
import '../handlers/mail_store.dart';

/// Dialog for viewing a received mail message.
/// Returns an action string: 'reply', 'forward', 'delete', or null.
class MailViewerDialog extends StatelessWidget {
  final WinlinkMail mail;

  const MailViewerDialog({super.key, required this.mail});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MAIL', style: TextStyle(fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                  color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              _field('From', mail.from, colors),
              _field('To', mail.to, colors),
              _field('Date', _formatDate(mail.date), colors),
              _field('Subject', mail.subject, colors),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(mail.body,
                      style: TextStyle(fontSize: 11, color: colors.onSurface,
                          height: 1.5)),
                ),
              ),
              if (mail.attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${mail.attachments.length} attachment(s)',
                    style: TextStyle(fontSize: 10,
                        color: colors.onSurfaceVariant)),
              ],
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context, 'reply'),
                    child: Text('REPLY', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1,
                        color: colors.primary))),
                TextButton(onPressed: () => Navigator.pop(context, 'forward'),
                    child: Text('FORWARD', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1,
                        color: colors.primary))),
                TextButton(onPressed: () => Navigator.pop(context, 'delete'),
                    child: Text('DELETE', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1,
                        color: colors.error))),
                const SizedBox(width: 8),
                TextButton(onPressed: () => Navigator.pop(context),
                    child: Text('CLOSE', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1,
                        color: colors.onSurfaceVariant))),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, String value, ColorScheme colors) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 10,
          fontWeight: FontWeight.w600, color: colors.onSurfaceVariant))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 11,
          color: colors.onSurface))),
    ]),
  );

  String _formatDate(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
