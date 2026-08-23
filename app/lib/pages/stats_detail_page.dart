import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../models/record.dart';
import '../services/record_service.dart';
import '../utils/formatters.dart';
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
    if (!mounted) return;
    setState(() {
      _records = records;
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
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final grouped = _grouped;
    final sortedKeys = _sortedKeys;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: colorBackgroundPage,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const SizedBox()
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 5),
                        children: sortedKeys.asMap().entries.map((entry) {
                          final key = entry.value;
                          final dayRecords = grouped[key]!;
                          final date = dayRecords.first.date;
                          final dayExp = dayRecords.where((r) => r.isExpense).fold(0, (s, r) => s + r.amountCents);
                          final dayInc = dayRecords.where((r) => !r.isExpense).fold(0, (s, r) => s + r.amountCents);
                          final expanded = _expandedDays.contains(key);
                          return Container(
                            margin: const EdgeInsets.fromLTRB(spacingM, 5, spacingM, 5),
                            decoration: BoxDecoration(
                              color: colorBackgroundCard,
                              borderRadius: BorderRadius.circular(radiusMedium),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() {
                                    if (_expandedDays.contains(key)) {
                                      _expandedDays.remove(key);
                                    } else {
                                      _expandedDays.add(key);
                                    }
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: 14),
                                    child: Row(
                                      children: [
                                        Text(formatDate(date), style: textBody),
                                        const Spacer(),
                                        Text.rich(
                                          TextSpan(
                                            style: textItemSub,
                                            children: [
                                              const TextSpan(text: '收入 '),
                                              TextSpan(text: formatAmount(dayInc), style: const TextStyle(fontWeight: FontWeight.w700, color: colorTextPrimary)),
                                              const TextSpan(text: '  支出 '),
                                              TextSpan(text: formatAmount(dayExp), style: const TextStyle(fontWeight: FontWeight.w700, color: colorTextPrimary)),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: spacingXS),
                                        Icon(expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: iconSizeSmall, color: colorTextSecondary),
                                      ],
                                    ),
                                  ),
                                ),
                                if (expanded) ...[
                                  const Divider(height: 1, thickness: borderWidthThin, color: colorDivider),
                                  ...dayRecords.map((r) => RecordItem(record: r, readonly: true)),
                                  const Divider(height: 1, thickness: borderWidthThin, color: colorDivider),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingS),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        const Text('结余：', style: textSecondary),
                                        Text(formatAmount(dayInc - dayExp), style: textBalance),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
    );
  }

}
