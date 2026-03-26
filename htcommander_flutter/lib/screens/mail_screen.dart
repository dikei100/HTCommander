import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../handlers/mail_store.dart';
import '../widgets/glass_card.dart';

class MailScreen extends StatefulWidget {
  const MailScreen({super.key});

  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  final DataBrokerClient _broker = DataBrokerClient();
  String _selectedFolder = 'Inbox';
  int _selectedMailIndex = -1;
  List<WinlinkMail> _allMails = [];

  final List<String> _folders = [
    'Inbox',
    'Outbox',
    'Draft',
    'Sent',
    'Archive',
    'Trash',
  ];

  final Map<String, IconData> _folderIcons = {
    'Inbox': Icons.inbox,
    'Outbox': Icons.outbox,
    'Draft': Icons.drafts,
    'Sent': Icons.send,
    'Archive': Icons.archive,
    'Trash': Icons.delete_outline,
  };

  @override
  void initState() {
    super.initState();
    _broker.subscribe(1, 'Mails', _onMails);
    final store = DataBroker.getDataHandlerTyped<MailStore>('MailStore');
    if (store != null) _allMails = store.getAllMails();
  }

  void _onMails(int deviceId, String name, Object? data) {
    if (data is List<WinlinkMail>) {
      setState(() {
        _allMails = data;
        final filtered = _filteredMails;
        if (_selectedMailIndex >= filtered.length) _selectedMailIndex = -1;
      });
    }
  }

  List<WinlinkMail> get _filteredMails =>
      _allMails.where((m) => m.folder == _selectedFolder).toList();

  int _folderCount(String folder) =>
      _allMails.where((m) => m.folder == folder).length;

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  void _checkForMail() {
    _broker.dispatch(1, 'WinlinkSync', null, store: false);
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  Widget _buildMobileFolderBar(ColorScheme colors) {
    return Container(
      height: 44,
      color: colors.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: _folders.map((folder) {
            final isSelected = folder == _selectedFolder;
            final count = _folderCount(folder);
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                selected: isSelected,
                showCheckmark: false,
                avatar: Icon(
                  _folderIcons[folder],
                  size: 14,
                  color: isSelected ? colors.primary : colors.onSurfaceVariant,
                ),
                label: Text(
                  count > 0 ? '$folder ($count)' : folder,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                onSelected: (_) => setState(() {
                  _selectedFolder = folder;
                  _selectedMailIndex = -1;
                }),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width > 800;

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Folder sidebar
          SizedBox(
            width: 180,
            child: _buildFolderSidebar(colors),
          ),
          // Mail content area
          Expanded(
            child: Column(
              children: [
                // Action bar
                _buildActionBar(colors),
                // Content
                Expanded(child: _buildMailContent(colors)),
              ],
            ),
          ),
        ],
      );
    }

    // Mobile: folder chips on top, then action bar, then content
    return Column(
      children: [
        _buildMobileFolderBar(colors),
        _buildActionBar(colors),
        Expanded(child: _buildMailContent(colors)),
      ],
    );
  }

  Widget _buildActionBar(ColorScheme colors) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: colors.surfaceContainer,
      child: Row(
        children: [
          Text(
            'FUNK-MAIL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.tertiary.withAlpha(30),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'WINLINK: IDLE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: colors.tertiary,
              ),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.edit, size: 14),
            label: const Text('Compose'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _checkForMail,
            icon: const Icon(Icons.sync, size: 14),
            label: const Text('Check Mail'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderSidebar(ColorScheme colors) {
    return Container(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              'FOLDERS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _folders.length,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, index) {
                final folder = _folders[index];
                final isSelected = folder == _selectedFolder;
                final count = _folderCount(folder);

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() {
                      _selectedFolder = folder;
                      _selectedMailIndex = -1;
                    }),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: isSelected
                            ? colors.primaryContainer.withAlpha(51)
                            : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _folderIcons[folder],
                            size: 16,
                            color: isSelected
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              folder,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? colors.onSurface
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (count > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.primary.withAlpha(25),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
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

  Widget _buildMailContent(ColorScheme colors) {
    final mails = _filteredMails;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          // Mail list
          Expanded(
            flex: 3,
            child: GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          'MESSAGES',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${mails.length} items',
                          style: TextStyle(
                            fontSize: 9,
                            color: colors.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: mails.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.mail_outline, size: 28,
                                    color: colors.outline),
                                const SizedBox(height: 8),
                                Text('No messages',
                                    style: TextStyle(
                                        fontSize: 11, color: colors.outline)),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
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
                                  letterSpacing: 1,
                                  color: colors.onSurfaceVariant,
                                ),
                                dataTextStyle: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurface,
                                ),
                                columns: const [
                                  DataColumn(label: Text('CALLSIGN')),
                                  DataColumn(label: Text('SUBJECT')),
                                  DataColumn(label: Text('DATE')),
                                ],
                                rows: List.generate(mails.length, (index) {
                                  final mail = mails[index];
                                  final isSelected =
                                      index == _selectedMailIndex;
                                  return DataRow(
                                    selected: isSelected,
                                    color: WidgetStateProperty.resolveWith(
                                        (states) {
                                      if (states
                                          .contains(WidgetState.selected)) {
                                        return colors.primaryContainer
                                            .withAlpha(60);
                                      }
                                      return null;
                                    }),
                                    onSelectChanged: (_) {
                                      setState(
                                          () => _selectedMailIndex = index);
                                    },
                                    cells: [
                                      DataCell(Text(mail.from,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: colors.primary,
                                          ))),
                                      DataCell(Text(mail.subject)),
                                      DataCell(Text(_formatDate(mail.date),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: colors.onSurfaceVariant,
                                          ))),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Message viewer
          Expanded(
            flex: 2,
            child: GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          'MESSAGE VIEWER',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (_selectedMailIndex >= 0 &&
                            _selectedMailIndex < mails.length) ...[
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              textStyle: const TextStyle(fontSize: 10),
                            ),
                            child: const Text('Reply'),
                          ),
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              textStyle: const TextStyle(fontSize: 10),
                            ),
                            child: const Text('Forward'),
                          ),
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              textStyle: const TextStyle(fontSize: 10),
                              foregroundColor: colors.error,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: _selectedMailIndex >= 0 &&
                              _selectedMailIndex < mails.length
                          ? SelectableText(
                              mails[_selectedMailIndex].body,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: colors.onSurface,
                                height: 1.5,
                              ),
                            )
                          : Center(
                              child: Text(
                                'Select a message to preview',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.outline,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
