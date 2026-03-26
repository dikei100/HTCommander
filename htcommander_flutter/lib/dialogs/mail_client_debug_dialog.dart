import 'package:flutter/material.dart';
import '../core/data_broker_client.dart';

/// Dialog for viewing Winlink/SMTP-IMAP protocol debug log.
class MailClientDebugDialog extends StatefulWidget {
  const MailClientDebugDialog({super.key});

  @override
  State<MailClientDebugDialog> createState() => _MailClientDebugDialogState();
}

class _MailClientDebugDialogState extends State<MailClientDebugDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  final ScrollController _scrollController = ScrollController();
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _broker.subscribe(1, 'WinlinkStateMessage', _onMessage);
  }

  @override
  void dispose() {
    _broker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onMessage(int deviceId, String name, Object? data) {
    if (data is String) {
      setState(() {
        _logLines.add(data);
        if (_logLines.length > 500) _logLines.removeAt(0);
      });
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PROTOCOL DEBUG LOG', style: TextStyle(fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                  color: colors.onSurfaceVariant)),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: _logLines.isEmpty
                      ? Center(child: Text('Waiting for protocol messages...',
                          style: TextStyle(fontSize: 11,
                              color: colors.onSurfaceVariant)))
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: _logLines.length,
                          itemBuilder: (_, i) => Text(_logLines[i],
                              style: TextStyle(fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: colors.onSurface, height: 1.4)),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => setState(() => _logLines.clear()),
                    child: Text('CLEAR', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1,
                        color: colors.onSurfaceVariant))),
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
}
