import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../models/record.dart';
import '../services/ledger_service.dart';
import '../services/record_service.dart';
import '../utils/formatters.dart';
import '../widgets/common_app_bar.dart';
import '../widgets/day_card.dart';
import '../widgets/record_item.dart';

class StatsDetailPage extends StatefulWidget {
  final DateTime start;
  final DateTime end;
  final String title;

  const StatsDetailPage({
    super.key,
    required this.start,
    required this.end,
    required this.title,
  });

  @override
  State<StatsDetailPage> createState() => _StatsDetailPageState();
}

class _StatsDetailPageState extends State<StatsDetailPage> {
  List<Record> _records = [];
  bool _loading = true;
  bool _isShared = false;
  final Set<String> _expandedDays = {};
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final ledgerId = currentLedgerId.value;
    if (ledgerId == null) return;
    final records = await loadRecordsByDateRange(
      ledgerId: ledgerId,
      start: widget.start,
      end: widget.end,
    );
    var shared = false;
    for (final l in await loadLedgers()) {
      if (l.id == ledgerId) {
        shared = l.syncMode == 1;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _records = records;
      _isShared = shared;
      _loading = false;
      if (!_initialized && _sortedKeys.isNotEmpty) {
        _expandedDays.add(_sortedKeys.first);
        _initialized = true;
      }
    });
  }

  Map<String, List<Record>> get _grouped {
    final map = <String, List<Record>>{};
    for (final r in _records) {
      final key = formatDateYmd(r.date);
      map.putIfAbsent(key, () => []).add(r);
    }
    return map;
  }

  List<String> get _sortedKeys =>
      _grouped.keys.toList()..sort((a, b) => b.compareTo(a));

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final sortedKeys = _sortedKeys;

    return Scaffold(
      appBar: CommonAppBar(title: widget.title),
      backgroundColor: colorBackgroundPage,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? const SizedBox()
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: spacingXS),
                    children: sortedKeys.asMap().entries.map((entry) {
                      final key = entry.value;
                      final dayRecords = grouped[key]!;
                      final expanded = _expandedDays.contains(key);
                      return DayCard(
                        dayRecords: dayRecords,
                        expanded: expanded,
                        isShared: _isShared,
                        margin: const EdgeInsets.fromLTRB(
                          spacingM,
                          5,
                          spacingM,
                          5,
                        ),
                        onToggle: () => setState(() {
                          if (_expandedDays.contains(key)) {
                            _expandedDays.remove(key);
                          } else {
                            _expandedDays.add(key);
                          }
                        }),
                        recordBuilder: (context, r) =>
                            RecordItem(record: r, readonly: true),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }
}
