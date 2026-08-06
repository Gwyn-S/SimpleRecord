import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../theme.dart';
import '../models/record.dart';
import '../services/record_service.dart';
import '../utils/calendar_utils.dart';
import '../utils/formatters.dart';
import '../widgets/record_item.dart';
import '../widgets/summary_block.dart';
import '../widgets/home_top_bar.dart';

class BillsPage extends StatefulWidget {
  const BillsPage({super.key});

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  final Set<String> _expandedDays = {};
  bool _initialized = false;
  @override
  void initState() {
    super.initState();
    allRecords.addListener(_onRecordsChanged);
    _onRecordsChanged();
  }

  @override
  void dispose() {
    allRecords.removeListener(_onRecordsChanged);
    super.dispose();
  }

  void _onRecordsChanged() {
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta);
      _expandedDays.clear();
      _initialized = false;
    });
  }

  String get _monthLabel => formatMonthLabel(_currentMonth);

  List<Record> get _monthRecords => monthRecords(_currentMonth);

  double get _monthIncome => monthIncome(_monthRecords);

  double get _monthExpense => monthExpense(_monthRecords);

  double get _monthBalance => _monthIncome - _monthExpense;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) {
            return Container(
              color: color,
              child: Column(
                children: [
                  SizedBox(height: MediaQuery.of(context).padding.top),
                  HomeTopBar(
                    monthLabel: _monthLabel,
                    onPrevMonth: () => _changeMonth(-1),
                    onNextMonth: () => _changeMonth(1),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(spacingXXL, 0, spacingXXL, spacingXS),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final halfW = constraints.maxWidth / 2;
                        return SizedBox(
                          height: heightSummaryArea,
                          child: Stack(
                            children: [
                              Positioned(left: 0, top: 0, width: halfW, height: heightSummaryLarge, child: SummaryBlock('本月结余', formatAmount(_monthBalance), large: true)),
                              Positioned(left: halfW, top: heightSummaryArea / 3, width: halfW, child: SummaryBlock('本月收入', formatAmount(_monthIncome))),
                              Positioned(left: 0, top: heightSummaryLarge, width: halfW, child: SummaryBlock('剩余预算', null, emptyText: '点此设置')),
                              Positioned(left: halfW, top: heightSummaryLarge, width: halfW, child: SummaryBlock('本月支出', formatAmount(_monthExpense))),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async { allRecords.value = await loadRecords(); },
            child: _buildRecordList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordList() {
    if (_loading) {
      return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    }
    final records = _monthRecords;
    if (records.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('暂无记录', style: TextStyle(fontSize: 14, color: colorTextSecondary)),
        ),
      );
    }
    final grouped = <String, List<Record>>{};
    for (final r in records) {
      final key = '${r.date.year}-${r.date.month}-${r.date.day}';
      grouped.putIfAbsent(key, () => []).add(r);
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    if (sortedKeys.isNotEmpty && !_initialized) {
      _expandedDays.add(sortedKeys.first);
      _initialized = true;
    }

    return Column(
      children: sortedKeys.map((key) {
        final dayRecords = grouped[key]!;
        final date = dayRecords.first.date;
        final dayExp = monthExpense(dayRecords);
        final dayInc = monthIncome(dayRecords);
        final expanded = _expandedDays.contains(key);
        return Container(
          margin: const EdgeInsets.fromLTRB(spacingM, spacingSM, spacingM, spacingSM),
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
                  padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        formatDate(date),
                        style: const TextStyle(fontSize: 14, color: colorTextPrimary),
                      ),
                      const Spacer(),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(fontSize: 12, color: colorTextSecondary),
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
                ...dayRecords.map((r) => RecordItem(record: r)),
                const Divider(height: 1, thickness: borderWidthThin, color: colorDivider),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingS),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('结余：', style: TextStyle(fontSize: 13, color: colorTextSecondary)),
                      Text(
                        formatAmount(dayInc - dayExp),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colorTextPrimary),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
