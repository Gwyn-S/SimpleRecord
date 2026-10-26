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
  // 上次成功加载的月份/账本：与本次一致则不重置展开状态（增删改后保留
  // 位置）；变了则在数据落地同一帧清空重置（切月/切账本）。
  DateTime? _loadedMonth;
  String? _loadedLedgerId;

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
    final ledgerId = currentLedgerId.value;
    // 三路查询并行发出：一次刷新原本串行跑三趟数据库往返，数据多时
    // 叠加锁排队，切月/切账本的数据等待被拉长，落地跳变就更明显。
    final recordsF = loadRecords(ledgerId: ledgerId, month: month);
    final budgetF = BudgetService.instance.getTotalBudget(ledgerId ?? '');
    final sharedF = ledgerId == null
        ? Future<bool>.value(false)
        : SyncService.instance.isSharedBook(ledgerId);
    final records = await recordsF;
    final monthBudget = await budgetF;
    final shared = await sharedF;
    if (seq != _loadSeq || !mounted) return;
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
      // 切月/切账本：在数据落地同一帧清空展开状态并重置默认展开资格。
      // 不提前清：提前清会在新数据到来前先渲染一帧旧的展开状态（闪旧数据）。
      final monthSwitched = _loadedMonth != null &&
          (month.year != _loadedMonth!.year ||
              month.month != _loadedMonth!.month);
      final ledgerSwitched =
          _loadedLedgerId != null && ledgerId != _loadedLedgerId;
      if (monthSwitched || ledgerSwitched) {
        _expandedDays.clear();
        _initialized = false;
      }
      _loadedMonth = month;
      _loadedLedgerId = ledgerId;
      _expandedDays.removeWhere((k) => !_sortedKeys.contains(k));
      // 默认展开最新一天（首次加载/切月/切账本后的第一屏）。必须与数据
      // 到达同帧判定：放在 build 里会被旧数据重建抢先消费掉 !_initialized
      // 资格，导致新月份/新账本不默认展开。
      if (!_initialized && _sortedKeys.isNotEmpty) {
        _expandedDays.add(_sortedKeys.first);
        _initialized = true;
      }
      // 记一笔后：展开刚记的那一天；不在当前月则保留，等切到该月再展开。
      final focus = focusRecordDay.value;
      if (focus != null) {
        final k = formatDateYmd(focus);
        if (_sortedKeys.contains(k)) {
          _expandedDays.add(k);
          focusRecordDay.value = null;
        }
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
    // 展开/初始化状态的清空移到 _onRecordsChanged 数据落地同帧处理，
    // 避免"新数据未到"时先渲染一帧旧列表（闪旧数据）。
    currentMonth.value = next;
  }

  Future<void> _openMonthPicker(BuildContext context) async {
    final target = await showMonthYearPicker(context, currentMonth.value);
    if (target == null || !mounted) return;
    if (target.year == currentMonth.value.year &&
        target.month == currentMonth.value.month) {
      return;
    }
    // 同 _changeMonth：清空与重置移到数据落地同帧处理，避免闪旧数据。
    currentMonth.value = target;
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

    // 惰性构建：只构建可见卡片。数据多时整月一次性构建会在切换落地帧
    // 掉帧（表现为闪），builder 把构建成本摊到滚动过程中。
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 5),
      itemCount: _sortedKeys.length,
      itemBuilder: (context, index) {
        final isFirst = index == 0;
        final key = _sortedKeys[index];
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
      },
    );
  }
}
