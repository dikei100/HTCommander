import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../widgets/glass_card.dart';

class ContactEntry {
  String callsign;
  String name;
  String type;
  String description;

  ContactEntry({
    required this.callsign,
    required this.name,
    required this.type,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'callsign': callsign,
        'name': name,
        'type': type,
        'description': description,
      };

  factory ContactEntry.fromJson(Map<String, dynamic> json) => ContactEntry(
        callsign: json['callsign'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final DataBrokerClient _broker = DataBrokerClient();
  List<ContactEntry> _contacts = [];
  int? _selectedIndex;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _broker.subscribe(0, 'Contacts', _onContacts);
    _loadContacts();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  void _loadContacts() {
    final raw = DataBroker.getValue<String>(0, 'Contacts', '');
    if (raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() {
          _contacts = list
              .map((e) => ContactEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } catch (_) {
        // Ignore malformed data
      }
    }
  }

  void _onContacts(int deviceId, String name, Object? data) {
    if (data is String) {
      try {
        final list = jsonDecode(data) as List;
        setState(() {
          _contacts = list
              .map((e) => ContactEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } catch (_) {
        // Ignore malformed data
      }
    }
  }

  void _saveContacts() {
    final json = jsonEncode(_contacts.map((c) => c.toJson()).toList());
    DataBroker.dispatch(0, 'Contacts', json);
  }

  void _addContact() {
    setState(() {
      _contacts.add(ContactEntry(
        callsign: '',
        name: '',
        type: '',
        description: '',
      ));
      _selectedIndex = _contacts.length - 1;
    });
    _saveContacts();
  }

  void _removeContact() {
    if (_selectedIndex == null || _selectedIndex! >= _contacts.length) return;
    setState(() {
      _contacts.removeAt(_selectedIndex!);
      _selectedIndex = null;
    });
    _saveContacts();
  }

  List<ContactEntry> get _filteredContacts {
    if (_searchQuery.isEmpty) return _contacts;
    return _contacts.where((c) {
      return c.callsign.toLowerCase().contains(_searchQuery) ||
          c.name.toLowerCase().contains(_searchQuery) ||
          c.type.toLowerCase().contains(_searchQuery) ||
          c.description.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _broker.dispose();
    super.dispose();
  }

  Widget _buildRosterColumn(ColorScheme colors, List<ContactEntry> filtered, int activeCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row with badge and actions
        Row(
          children: [
            Text(
              'STATION ROSTER',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.primary.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$activeCount ACTIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: colors.primary,
                ),
              ),
            ),
            const Spacer(),
            _ActionButton(
              icon: Icons.add_rounded,
              label: 'Add',
              onPressed: _addContact,
              colors: colors,
            ),
            const SizedBox(width: 6),
            _ActionButton(
              icon: Icons.delete_outline_rounded,
              label: 'Remove',
              onPressed:
                  _selectedIndex != null ? _removeContact : null,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Search bar
        GlassCard(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          child: Row(
            children: [
              Icon(Icons.search_rounded,
                  size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search callsign, name, type...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant.withAlpha(120),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                GestureDetector(
                  onTap: () => _searchController.clear(),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: colors.onSurfaceVariant),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Contact table
        Expanded(
          child: GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh.withAlpha(60),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8)),
                  ),
                  child: Row(
                    children: [
                      _tableHeader('CALLSIGN', flex: 2, colors: colors),
                      _tableHeader('SNR', flex: 1, colors: colors),
                      _tableHeader('LAST HEARD',
                          flex: 2, colors: colors),
                      _tableHeader('STATUS', flex: 1, colors: colors),
                    ],
                  ),
                ),
                // Table body
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? 'No matching stations'
                                : 'No stations in roster',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.outline,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final c = filtered[i];
                            final realIndex =
                                _contacts.indexOf(c);
                            final isSelected =
                                _selectedIndex == realIndex;
                            final isOnline =
                                c.callsign.isNotEmpty;

                            return GestureDetector(
                              onTap: () {
                                setState(
                                    () => _selectedIndex = realIndex);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 9),
                                margin: const EdgeInsets.only(
                                    top: 1),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? colors.primary.withAlpha(25)
                                      : Colors.transparent,
                                ),
                                child: Row(
                                  children: [
                                    // Callsign
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        c.callsign.isNotEmpty
                                            ? c.callsign
                                            : '--',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? colors.primary
                                              : colors.onSurface,
                                        ),
                                      ),
                                    ),
                                    // SNR (derived from type field)
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        c.type.isNotEmpty
                                            ? c.type
                                            : '--',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.onSurface,
                                        ),
                                      ),
                                    ),
                                    // Last heard (derived from description)
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        c.description.isNotEmpty
                                            ? c.description
                                            : '--',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              colors.onSurfaceVariant,
                                        ),
                                        overflow:
                                            TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // Status badge
                                    Expanded(
                                      flex: 1,
                                      child: Align(
                                        alignment:
                                            Alignment.centerLeft,
                                        child: _StatusBadge(
                                            isOnline: isOnline),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filtered = _filteredContacts;
    final activeCount =
        _contacts.where((c) => c.callsign.isNotEmpty).length;
    final isWide = MediaQuery.sizeOf(context).width > 800;

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left panel: roster list
            Expanded(
              flex: 3,
              child: _buildRosterColumn(colors, filtered, activeCount),
            ),
            const SizedBox(width: 14),
            // Right panel: detail
            SizedBox(
              width: 300,
              child: _buildDetailPanel(colors),
            ),
          ],
        ),
      );
    }

    // Mobile: just the roster column, full width
    return Padding(
      padding: const EdgeInsets.all(12),
      child: _buildRosterColumn(colors, filtered, activeCount),
    );
  }

  Widget _tableHeader(String label,
      {required int flex, required ColorScheme colors}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildDetailPanel(ColorScheme colors) {
    final contact =
        _selectedIndex != null && _selectedIndex! < _contacts.length
            ? _contacts[_selectedIndex!]
            : null;

    if (contact == null) {
      return GlassCard(
        child: SizedBox(
          height: double.infinity,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline_rounded,
                    size: 32, color: colors.outline.withAlpha(80)),
                const SizedBox(height: 8),
                Text(
                  'Select a station',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contact header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        contact.callsign.isNotEmpty
                            ? contact.callsign[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.callsign.isNotEmpty
                              ? contact.callsign
                              : 'No Callsign',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        if (contact.name.isNotEmpty)
                          Text(
                            contact.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _StatusBadge(isOnline: contact.callsign.isNotEmpty),
                ],
              ),
              const SizedBox(height: 20),

              // Hardware Signature section
              _sectionHeader('HARDWARE SIGNATURE', colors),
              const SizedBox(height: 10),
              _detailRow('Node Type', contact.type.isNotEmpty ? contact.type : '--', colors),
              const SizedBox(height: 6),
              _detailRow('Firmware', '--', colors),
              const SizedBox(height: 6),
              _detailRow('Antenna', '--', colors),
              const SizedBox(height: 6),
              _detailRow('Power Source', '--', colors),
              const SizedBox(height: 20),

              // Frequency Profile section
              _sectionHeader('FREQUENCY PROFILE', colors),
              const SizedBox(height: 10),
              if (contact.description.isNotEmpty)
                Text(
                  contact.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface,
                    height: 1.5,
                  ),
                )
              else
                Text(
                  'No frequencies logged',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.outline,
                  ),
                ),
              const SizedBox(height: 20),

              // Transmission History section
              _sectionHeader('TRANSMISSION HISTORY', colors),
              const SizedBox(height: 10),
              Text(
                'No transmissions recorded',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.outline,
                ),
              ),
              const SizedBox(height: 20),

              // Clear Log button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    // Clear description as log placeholder
                    if (_selectedIndex != null &&
                        _selectedIndex! < _contacts.length) {
                      setState(() {
                        _contacts[_selectedIndex!].description = '';
                      });
                      _saveContacts();
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colors.error,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(
                        color: colors.error.withAlpha(60),
                      ),
                    ),
                  ),
                  child: const Text(
                    'Clear Log',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String label, ColorScheme colors) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: colors.onSurfaceVariant,
      ),
    );
  }

  Widget _detailRow(String label, String value, ColorScheme colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isOnline});
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = isOnline ? 'Online' : 'Offline';
    final bgColor = isOnline
        ? colors.tertiary.withAlpha(30)
        : colors.error.withAlpha(30);
    final textColor = isOnline ? colors.tertiary : colors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.colors,
    this.onPressed,
  });
  final IconData icon;
  final String label;
  final ColorScheme colors;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon,
          size: 14,
          color: enabled ? colors.primary : colors.onSurfaceVariant.withAlpha(80)),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: enabled ? colors.primary : colors.onSurfaceVariant.withAlpha(80),
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
