import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/stats_service.dart';
import '../services/theme_service.dart';
import '../utils/formatters.dart';
import '../widgets/card_container.dart';
import '../widgets/date_filter_sheet.dart';
import '../widgets/donut_pie_chart.dart';
import '../widgets/month_year_picker.dart';
import '../widgets/stats_ranking_card.dart';
import '../widgets/tab_bar.dart';
import '../widgets/tab_switcher_app_bar.dart';
import '../widgets/trend_line_chart.dart';
import 'stats_detail_page.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _isExpense = true;
  StatsRange _selectedRange = StatsRange.month;
  late int _selectedIndex;
  int _selectedYear = DateTime.now().year;
  final ScrollController _scrollController = ScrollController();
  final Map<StatsRange, int> _selectedIndexMap = {};
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _customEnd = DateTime.now();

  // 数据状态
  int _totalExpense = 0;
  int _totalIncome = 0;
  List<({String categoryName, int amountCents, int count})> _expenseByCategory = [];
  List<({String label, int amountCents})> _periodData = [];
  List<({String label, int amountCents})> _weekSummaryData = [];
  List<({String label, int amountCents})> _monthSummaryData = [];
  List<({String label, int amountCents})> _yearSummaryData = [];
  final Map<String, StatsData> _dataCache = {};

  List<String> get _rangeLabels => ['周', '月', '年', '自定义'];

  int get _lastIndex => _items.length - 1;

  String get _yearLabel {
    final now = DateTime.now().year;
    if (_selectedYear == now) return '今年';
    if (_selectedYear == now - 1) return '去年';
    if (_selectedYear == now - 2) return '前年';
    return '$_selectedYear';
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = _lastIndex;
    _selectedIndexMap[_selectedRange] = _selectedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToEnd();
      _loadData();
    });
  }

  void _scrollToEnd() {
    try {
      if (_scrollController.hasClients &&
          _scrollController.position.hasContentDimensions &&
          _scrollController.position.maxScrollExtent > 0) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        return;
      }
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (mounted &&
            _scrollController.hasClients &&
            _scrollController.position.hasContentDimensions &&
            _scrollController.position.maxScrollExtent > 0) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      } catch (_) {}
    });
  }

  ({DateTime start, DateTime end})? _getDateRange() {
    return getDateRange(
      range: _selectedRange,
      index: _selectedIndex,
      year: _selectedYear,
      totalItems: _items.length,
      customStart: _customStart,
      customEnd: _customEnd,
    );
  }

  Future<void> _loadData() async {
    try {
      final data = await loadStatsData(
        range: _selectedRange,
        index: _selectedIndex,
        year: _selectedYear,
        totalItems: _items.length,
        customStart: _customStart,
        customEnd: _customEnd,
      );
      
      if (!mounted || data == null) return;
      
      setState(() {
        _totalExpense = data.totalExpense;
        _totalIncome = data.totalIncome;
        _expenseByCategory = data.expenseByCategory;
        _periodData = data.periodData;
        _weekSummaryData = data.weekSummary;
        _monthSummaryData = data.monthSummary;
        _yearSummaryData = data.yearSummary;
      });
      
      final cacheKey = StatsCacheKey(
        range: _selectedRange,
        index: _selectedIndex,
        year: _selectedYear,
      );
      _dataCache[cacheKey.toString()] = data;
    } catch (e) {
      // 加载失败，保持当前状态
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<String> get _items => getRangeLabels(_selectedRange, _customStart);

  Future<void> _showYearPicker() async {
    final now = DateTime.now();
    final picked = await showYearPicker(
      context,
      DateTime(_selectedYear),
      maxYear: now.year,
    );
    if (picked != null && mounted) {
      setState(() => _selectedYear = picked.year);
      _loadData();
    }
  }

  Future<void> _showCustomDateFilter() async {
    final result = await showDialog<(DateTime?, DateTime?)>(
      context: context,
      builder: (context) => DateFilterSheet(
        initialStart: _customStart,
        initialEnd: _customEnd,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (result.$1 == null || result.$2 == null) {
          _customStart = DateTime.now().subtract(const Duration(days: 30));
          _customEnd = DateTime.now();
        } else {
          _customStart = result.$1!;
          _customEnd = result.$2!;
        }
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: TabSwitcherAppBar(
        tabs: const ['支出', '收入'],
        selectedIndex: _isExpense ? 0 : 1,
        onChanged: (i) => setState(() => _isExpense = i == 0),
        backgroundColor: themeColor,
      ),
      backgroundColor: colorBackgroundPage,
      body: ListView(
        padding: const EdgeInsets.all(spacingM),
        children: [
          Container(
            decoration: BoxDecoration(
              color: colorBackgroundCard,
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
            clipBehavior: Clip.antiAlias,
            child: FilterTabBar(
              tabs: _rangeLabels,
              selectedIndex: _selectedRange.index,
              onChanged: (i) {
                final newRange = StatsRange.values[i];
                _selectedIndexMap[_selectedRange] = _selectedIndex;
                _selectedRange = newRange;
                _selectedIndex = _selectedIndexMap[newRange] ?? _lastIndex;
                final cacheKey = StatsCacheKey(
                  range: _selectedRange,
                  index: _selectedIndex,
                  year: _selectedYear,
                );
                final cached = _dataCache[cacheKey.toString()];
                setState(() {
                  if (cached != null) {
                    _totalExpense = cached.totalExpense;
                    _totalIncome = cached.totalIncome;
                    _expenseByCategory = cached.expenseByCategory;
                    _periodData = cached.periodData;
                    _weekSummaryData = cached.weekSummary;
                    _monthSummaryData = cached.monthSummary;
                    _yearSummaryData = cached.yearSummary;
                  }
                });
                _loadData();
              },
            ),
          ),
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: spacingXS),
                    itemCount: _items.length,
                    separatorBuilder: (_, a) => const SizedBox(width: spacingXXS),
                    itemBuilder: (context, index) {
                      final isSelected = _selectedIndex == index;
                      return GestureDetector(
                        onTap: () {
                          if (_selectedRange == StatsRange.custom) {
                            _showCustomDateFilter();
                          } else {
                            setState(() {
                              _selectedIndex = index;
                              _selectedIndexMap[_selectedRange] = index;
                            });
                            _loadData();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: spacingM),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _items[index],
                                style: isSelected && _selectedRange != StatsRange.custom
                                    ? textTagSmall.copyWith(color: themeColor)
                                    : textTagSmall,
                              ),
                              if (_selectedRange == StatsRange.custom) ...[
                                const SizedBox(width: spacingXXS),
                                Icon(
                                  Icons.arrow_drop_down,
                                  size: 16,
                                  color: colorTextPrimary,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_selectedRange == StatsRange.week || _selectedRange == StatsRange.month) ...[
                  const SizedBox(width: spacingS),
                  GestureDetector(
                    onTap: _showYearPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: spacingM, vertical: spacingXS),
                      decoration: BoxDecoration(
                        color: colorBackgroundCard,
                        borderRadius: BorderRadius.circular(radiusSmall),
                      ),
                      child: Text(_yearLabel, style: textTagSmall),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _buildSummaryCard(),
          const SizedBox(height: spacingM),
          _buildTrendChart(),
          const SizedBox(height: spacingM),
          _buildPieChart(),
          const SizedBox(height: spacingM),
          _buildRankingCard(),
          const SizedBox(height: spacingM),
          _buildPeriodSummary(),
        ],
      ),
    );
  }

  void _openDetail() {
    final range = _getDateRange();
    if (range == null) return;
    final title = '${formatDateYmd(range.start)}~${formatDateYmd(range.end)}';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatsDetailPage(start: range.start, end: range.end, title: title),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final balance = _totalIncome - _totalExpense;
    final range = _getDateRange();
    int dailyAvg = 0;
    if (range != null) {
      final days = range.end.difference(range.start).inDays;
      if (days > 0) dailyAvg = _totalExpense ~/ days;
    }
    
    return CardContainer(
      title: '收支统计',
      trailing: _buildTrailingButton('详情', onTap: _openDetail),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: spacingS),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildSummaryItem('支出', _totalExpense)),
                Expanded(child: _buildSummaryItem('收入', _totalIncome)),
              ],
            ),
            const SizedBox(height: spacingM),
            Row(
              children: [
                Expanded(child: _buildSummaryItem('结余', balance)),
                Expanded(child: _buildSummaryItem('日均支出', dailyAvg)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, int amountCents) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: textItemSub),
        const SizedBox(height: spacingXS),
        Text(formatAmount(amountCents), style: textAmountSummary),
      ],
    );
  }

  Widget _buildTrailingButton(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap ?? () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: spacingM, vertical: spacingXS),
        decoration: BoxDecoration(
          color: colorDivider,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        child: Text(label, style: textTagSmall),
      ),
    );
  }

  Widget _buildTrendChart() {
    if (_periodData.isEmpty) {
      return CardContainer(
        title: '支出统计图',
        trailing: _buildTrailingButton('详情', onTap: _openDetail),
        child: const SizedBox(height: 160),
      );
    }

    final points = _periodData.map((e) => TrendPoint(
      label: e.label,
      value: e.amountCents,
    )).toList();

    return CardContainer(
      title: '支出统计图',
      trailing: _buildTrailingButton('详情', onTap: _openDetail),
      child: TrendLineChart(
        points: points,
        showMarkers: _selectedRange != StatsRange.year,
      ),
    );
  }

  Widget _buildPieChart() {
    if (_expenseByCategory.isEmpty) {
      return CardContainer(
        title: '支出占比',
        child: const SizedBox.shrink(),
      );
    }

    final total = _expenseByCategory.fold(0, (s, e) => s + e.amountCents);
    final colors = themeColorPalette;

    return CardContainer(
      title: '支出占比',
      child: SizedBox(
        height: 220,
        child: DonutPieChart(
          data: List.generate(_expenseByCategory.length, (i) {
            final item = _expenseByCategory[i];
            return PieSectorData(
              name: item.categoryName,
              amount: item.amountCents,
              color: colors[i % colors.length],
            );
          }),
          total: total,
        ),
      ),
    );
  }

  Widget _buildRankingCard() {
    return StatsRankingCard(
      title: '支出排行',
      items: _expenseByCategory.map((e) => RankingItem(
        name: e.categoryName,
        amountCents: e.amountCents,
        count: e.count,
      )).toList(),
    );
  }

  String get _periodTitle {
    switch (_selectedRange) {
      case StatsRange.week: return '周支出汇总';
      case StatsRange.month: return '月支出汇总';
      case StatsRange.year: return '年支出汇总';
      case StatsRange.custom: return '';
    }
  }

  Widget _buildPeriodSummary() {
    if (_selectedRange == StatsRange.custom) return const SizedBox.shrink();

    List<({String label, int amountCents})> summaryData;
    switch (_selectedRange) {
      case StatsRange.week: summaryData = _weekSummaryData; break;
      case StatsRange.month: summaryData = _monthSummaryData; break;
      case StatsRange.year: summaryData = _yearSummaryData; break;
      case StatsRange.custom: return const SizedBox.shrink();
    }

    if (summaryData.isEmpty) {
      return CardContainer(
        title: _periodTitle,
        child: const SizedBox(height: 160),
      );
    }

    final points = summaryData.map((e) => TrendPoint(
      label: e.label,
      value: e.amountCents,
    )).toList();

    return CardContainer(
      title: _periodTitle,
      child: TrendLineChart(points: points),
    );
  }
}
