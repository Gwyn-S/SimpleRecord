import 'package:flutter/material.dart';
import '../../constants/app_dimensions.dart';
import '../../services/core/theme_service.dart';
import '../../models/data/record.dart';
import '../../services/data/record_service.dart';
import '../../services/data/budget_service.dart';
import '../../services/cloud/sync_service.dart';
import '../../utils/calendar_utils.dart';
import 'budget_page.dart';
import '../../utils/formatters.dart';
import '../../widgets/record/day_card.dart';
import '../../widgets/record/record_item.dart';
import '../../widgets/chart/summary_block.dart';
import '../../widgets/record/home_top_bar.dart';
import '../../widgets/common/month_year_picker.dart';
import '../../utils/navigation.dart';

class BillsPage extends StatefulWidget {
  const BillsPage({super.key});

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  bool _loading = true;
  final Set<String> _expandedDays = {};
  bool _initialized = false;

  List<Record> _records = [];
  final Map<String, List<Record>> _grouped = {};
  List<String> _sortedKeys = [];
  int _monthIncome = 0;
  int _monthExpense = 0;
  int _monthBudget = 0;
  bool _isShared = false;

  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _onRecordsChanged();
    recordsVersion.addListener(_onRecordsChanged);
    currentLedgerId.addListener(_onRecordsChanged);
    currentMonth.addListener(_onRecordsChanged);
    budgetVersion.addListener(_onRecordsChanged);
  }

  @override
  void dispose() {
    recordsVersion.removeListener(_onRecordsChanged);
    currentLedgerId.removeListener(_onRecordsChanged);
    currentMonth.removeListener(_onRecordsChanged);
    budgetVersion.removeListener(_onRecordsChanged);
    super.dispose();
  }

  Future<void> _onRecordsChanged() async {
    final seq = ++_loadSeq;
    final month = currentMonth.value;
    final records = await loadRecords(
      ledgerId: currentLedgerId.value,
      month: month,
    );
    final monthBudget = await BudgetService.instance.getTotalBudget(
      currentLedgerId.value ?? '',
    );
    final ledgerId = currentLedgerId.value;
    var shared =
        ledgerId != null && await SyncService.instance.isSharedBook(ledgerId);
    if (seq != _loadSeq || !mounted) return;
    final prevExpanded = {..._expandedDays};
    setState(() {
      _isShared = shared;
      _records = records;
      _grouped.clear();
      for (final r in records) {
        final key = formatDateYmd(r.date);
        _grouped.putIfAbsent(key, () => []).add(r);
      }
      _sortedKeys = _grouped.keys.toList()..sort((a, b) => b.compareTo(a));
      _monthIncome = monthIncome(records);
      _monthExpense = monthExpense(records);
      _monthBudget = monthBudget;
      if (!_initialized) {
        _expandedDays.clear();
        if (_sortedKeys.isNotEmpty) {
          _expandedDays.add(_sortedKeys.first);
        }
      } else {
        _expandedDays.removeWhere((k) => !_sortedKeys.contains(k));
      }
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    final next = DateTime(
      currentMonth.value.year,
      currentMonth.value.month + delta,
    );
    if (next.year == currentMonth.value.year &&
        next.month == currentMonth.value.month) {
      return;
    }
    currentMonth.value = next;
    setState(() {
      _expandedDays.clear();
      _initialized = false;
    });
  }

  Future<void> _openMonthPicker(BuildContext context) async {
    final target = await showMonthYearPicker(context, currentMonth.value);
    if (target == null || !mounted) return;
    if (target.year == currentMonth.value.year &&
        target.month == currentMonth.value.month) {
      return;
    }
    currentMonth.value = target;
    setState(() {
      _expandedDays.clear();
      _initialized = false;
    });
  }

  String get _monthLabel => formatMonthLabel(currentMonth.value);

  int get _monthBalance => _monthIncome - _monthExpense;

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Column(
      children: [
        Container(
          color: themeColor,
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top),
              HomeTopBar(
                monthLabel: _monthLabel,
                onPrevMonth: () => _changeMonth(-1),
                onNextMonth: () => _changeMonth(1),
                onMonthLabelTap: () => _openMonthPicker(context),
                onLedgerTap: () => openLedgerList(context),
                onBackupTap: () => openBackup(context),
                onSearchTap: () => openSearch(context),
                onUserTap: () => openUser(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  spacingXXL,
                  0,
                  spacingXXL,
                  0,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final halfW = constraints.maxWidth / 2;
                    return SizedBox(
                      height: heightSummaryArea,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            width: halfW,
                            height: heightSummaryLarge,
                            child: SummaryBlock(
                              '本月结余',
                              formatAmount(_monthBalance),
                              large: true,
                            ),
                          ),
                          Positioned(
                            left: halfW,
                            top: 0,
                            width: halfW,
                            height: heightSummaryLarge,
                            child: SummaryBlock(
                              '本月收入',
                              formatAmount(_monthIncome),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: heightSummaryLarge,
                            width: halfW,
                            height: heightSummaryArea - heightSummaryLarge,
                            child: SummaryBlock(
                              '剩余预算',
                              _monthBudget > 0
                                  ? formatAmount(_monthBudget - _monthExpense)
                                  : null,
                              emptyText: _monthBudget > 0 ? null : '点此设置',
                              onTap: () => openBudget(context),
                            ),
                          ),
                          Positioned(
                            left: halfW,
                            top: heightSummaryLarge,
                            width: halfW,
                            height: heightSummaryArea - heightSummaryLarge,
                            child: SummaryBlock(
                              '本月支出',
                              formatAmount(_monthExpense),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildRecordList()),
      ],
    );
  }

  Widget _buildRecordList() {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final records = _records;
    if (records.isEmpty) {
      return const SizedBox.shrink();
    }
    if (_sortedKeys.isNotEmpty && !_initialized) {
      _expandedDays.add(_sortedKeys.first);
      _initialized = true;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 5),
      children: _sortedKeys.asMap().entries.map((entry) {
        final isFirst = entry.key == 0;
        final key = entry.value;
        final dayRecords = _grouped[key]!;
        final expanded = _expandedDays.contains(key);
        return DayCard(
          dayRecords: dayRecords,
          expanded: expanded,
          isShared: _isShared,
          margin: EdgeInsets.fromLTRB(spacingM, isFirst ? 10 : 5, spacingM, 5),
          onToggle: () => setState(() {
            if (_expandedDays.contains(key)) {
              _expandedDays.remove(key);
            } else {
              _expandedDays.add(key);
            }
          }),
          recordBuilder: (context, r) => RecordItem(
            record: r,
            isShared: _isShared,
            onEdit: () => openEditRecord(context, r),
          ),
        );
      }).toList(),
    );
  }
}
