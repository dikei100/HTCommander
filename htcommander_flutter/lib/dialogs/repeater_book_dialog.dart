import 'package:flutter/material.dart';
import '../handlers/repeater_book_client.dart';
import '../radio/models/radio_channel_info.dart';

/// Dialog for searching and importing repeaters from RepeaterBook.
class RepeaterBookDialog extends StatefulWidget {
  const RepeaterBookDialog({super.key});

  @override
  State<RepeaterBookDialog> createState() => _RepeaterBookDialogState();
}

class _RepeaterBookDialogState extends State<RepeaterBookDialog> {
  final RepeaterBookClient _client = RepeaterBookClient();
  String _selectedCountry = 'United States';
  String _selectedState = '';
  List<RepeaterBookEntry> _results = [];
  List<RepeaterBookEntry> _selected = [];
  bool _loading = false;
  String? _error;

  List<String> get _states =>
      RepeaterBookClient.countries[_selectedCountry] ?? [];

  @override
  void initState() {
    super.initState();
    final states = _states;
    if (states.isNotEmpty) _selectedState = states[0];
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_selectedState.isEmpty && _states.isNotEmpty) return;
    setState(() { _loading = true; _error = null; _results = []; });
    try {
      _results = await _client.search(_selectedCountry, _selectedState);
      _selected = [];
    } on RepeaterBookRateLimitException {
      _error = 'Rate limit reached. Please wait and try again.';
    } catch (e) {
      _error = 'Search failed: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final countries = RepeaterBookClient.countries.keys.toList();

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('REPEATERBOOK SEARCH', style: TextStyle(fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 1,
                color: colors.onSurfaceVariant)),
            const SizedBox(height: 12),
            // Search controls
            Row(children: [
              Expanded(child: _dropdown('Country', _selectedCountry, countries,
                  (v) { setState(() { _selectedCountry = v; final s = _states; _selectedState = s.isNotEmpty ? s[0] : ''; }); }, colors)),
              const SizedBox(width: 8),
              if (_states.isNotEmpty)
                Expanded(child: _dropdown('State', _selectedState, _states,
                    (v) => setState(() => _selectedState = v), colors)),
              const SizedBox(width: 8),
              FilledButton(onPressed: _loading ? null : _search,
                  child: _loading
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('SEARCH', style: TextStyle(fontSize: 10,
                          letterSpacing: 1))),
            ]),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: TextStyle(fontSize: 11, color: colors.error)),
            // Results table
            Expanded(
              child: _results.isEmpty
                  ? Center(child: Text(
                      _loading ? 'Searching...' : 'No results. Search for repeaters above.',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)))
                  : SingleChildScrollView(child: DataTable(
                      headingRowHeight: 28, dataRowMinHeight: 24, dataRowMaxHeight: 28,
                      columnSpacing: 10, horizontalMargin: 8,
                      headingTextStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                          letterSpacing: 1, color: colors.onSurfaceVariant),
                      dataTextStyle: TextStyle(fontSize: 10, color: colors.onSurface),
                      columns: const [
                        DataColumn(label: Text('CALL')),
                        DataColumn(label: Text('FREQ'), numeric: true),
                        DataColumn(label: Text('PL')),
                        DataColumn(label: Text('CITY')),
                        DataColumn(label: Text('MODE')),
                      ],
                      rows: _results.map((r) => DataRow(
                        selected: _selected.contains(r),
                        onSelectChanged: (sel) {
                          setState(() {
                            if (sel == true) { _selected.add(r); }
                            else { _selected.remove(r); }
                          });
                        },
                        cells: [
                          DataCell(Text(r.callsign)),
                          DataCell(Text(r.frequency.toStringAsFixed(4))),
                          DataCell(Text(r.pl)),
                          DataCell(Text(r.nearestCity)),
                          DataCell(Text(r.mode)),
                        ],
                      )).toList(),
                    )),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${_results.length} results, ${_selected.length} selected',
                  style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
              Row(children: [
                TextButton(onPressed: () => Navigator.pop(context),
                    child: Text('CANCEL', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1,
                        color: colors.onSurfaceVariant))),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _selected.isEmpty ? null : () {
                      final channels = <RadioChannelInfo>[];
                      for (var i = 0; i < _selected.length; i++) {
                        final ch = RepeaterBookClient.toRadioChannel(_selected[i], i);
                        if (ch != null) channels.add(ch);
                      }
                      Navigator.pop(context, channels);
                    },
                    child: const Text('IMPORT', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1))),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> items,
      ValueChanged<String> onChanged, ColorScheme colors) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
          letterSpacing: 1, color: colors.onSurfaceVariant)),
      const SizedBox(height: 2),
      Container(
        height: 30, padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.outlineVariant)),
        child: DropdownButton<String>(value: items.contains(value) ? value : (items.isNotEmpty ? items[0] : null),
            underline: const SizedBox(), isDense: true, isExpanded: true,
            dropdownColor: colors.surfaceContainerHigh,
            style: TextStyle(fontSize: 10, color: colors.onSurface),
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) { if (v != null) onChanged(v); }),
      ),
    ]);
  }
}
