import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../services/data/record_service.dart';
import '../../services/data/stats_service.dart';
import '../../services/core/theme_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/card_container.dart';
import '../../widgets/record/date_filter_sheet.dart';
import '../../widgets/chart/donut_pie_chart.dart';
import '../../widgets/common/month_year_picker.dart';
import '../../widgets/chart/stats_ranking_card.dart';
import '../../widgets/common/tab_bar.dart';
import '../../widgets/common/tab_switcher_app_bar.dart';
import '../../widgets/chart/trend_line_chart.dart';
import 'stats_detail_page.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _isExpense = true;
  StatsRange _selectedRange = StatsRange.week;
  late int _selectedIndex;
  int _selectedYear = DateTime.now().year;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  final Map<StatsRange, int> _selectedIndexMap = {};
  final Map<StatsRange, double> _scrollOffsets = {};
  String _customPreset = '最近30天';
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _customEnd = DateTime.now();

  // 数据状态
  int _loadSeq = 0;
  int _totalExpense = 0;
  int _totalIncome = 0;
  List<({String categoryName, int amountCents, int count})> _expenseByCategory =
      [];
  List<({String label, int amountCents})> _periodData = [];
  List<({String label, int amountCents})> _weekSummaryData = [];
  List<({String label, int amountCents})> _monthSummaryData = [];
  List<({String label, int amountCents})> _yearSummaryData = [];
  final Map<String, StatsData> _dataCache = {};

  List<String> get _rangeLabels => ['周', '月', '年', '自定义'];

  int get _lastIndex => _items.length - 1;

  String get _yearLabel => yearLabel(_selectedYear);

  @override
  void initState() {
    super.initState();
    _selectedIndex = _lastIndex;
    _selectedIndexMap[_selectedRange] = _selectedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreScrollPosition();
      _loadData();
    });
    recordsVersion.addListener(_loadData);
    currentLedgerId.addListener(_loadData);
  }

  void _scrollToSelected() {
    void apply() {
      try {
        if (!mounted || !_scrollController.hasClients) return;
        final ctx = _itemKeys[_selectedIndex]?.currentContext;
        if (ctx != null && ctx.mounted) {
          // 目标项已构建：平滑滚动到视口居中。
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      } catch (_) {}
    }

    // 等一帧，确保 setState 引起重建后再定位。
    WidgetsBinding.instance.addPostFrameCallback((_) => apply());
  }

  /// 切回某 tab 时，把横向标签条恢复到离开前的滚动位置；
  /// 从未滚过的 tab 落到 maxScrollExtent（最新一项贴右端的默认位置）。
  void _restoreScrollPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final saved = _scrollOffsets[_selectedRange] ?? max;
      _scrollController.jumpTo(saved.clamp(0.0, max));
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

  /// 自定义范围内，若用户选的是"相对当天"的预设（本周/近三月/最近30天等），
  /// 每次加载都按当前日期重算起止，避免跨天仍停留在旧时间段；
  /// 手动选死的固定区间（如 2026-01-01~2026-01-31）保持不动。
  void _refreshCustomRangeIfRelative() {
    if (_selectedRange != StatsRange.custom) return;
    final now = DateTime.now();
    final presets = datePresets(now);
    for (final p in presets) {
      if (p.label == _customPreset) {
        _customStart = p.start;
        _customEnd = p.end;
        return;
      }
    }
    if (_customPreset == '最近30天') {
      _customStart = now.subtract(const Duration(days: 30));
      _customEnd = now;
    }
  }

  Future<void> _loadData() async {
    try {
      final seq = ++_loadSeq;
      _refreshCustomRangeIfRelative();
      final data = await loadStatsData(
        range: _selectedRange,
        index: _selectedIndex,
        year: _selectedYear,
        totalItems: _items.length,
        customStart: _customStart,
        customEnd: _customEnd,
      );

      // 已有更新的查询发出：丢弃本次过期结果，避免旧数据覆盖新数据。
      if (!mounted || data == null || seq != _loadSeq) return;

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
        ledgerId: currentLedgerId.value,
        customStart: _customStart,
        customEnd: _customEnd,
      );
      _dataCache[cacheKey.toString()] = data;
    } catch (e) {
      // 加载失败，保持当前状态
    }
  }

  @override
  void dispose() {
    recordsVersion.removeListener(_loadData);
    currentLedgerId.removeListener(_loadData);
    _scrollController.dispose();
    super.dispose();
  }

  List<String> get _items {
    if (_selectedRange == StatsRange.custom) {
      return [_customPreset];
    }
    return getRangeLabels(_selectedRange, _customStart);
  }

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
      builder: (context) =>
          DateFilterSheet(initialStart: _customStart, initialEnd: _customEnd),
    );
    if (result != null && mounted) {
      setState(() {
        if (result.$1 == null || result.$2 == null) {
          _customStart = DateTime.now().subtract(const Duration(days: 30));
          _customEnd = DateTime.now();
          _customPreset = '最近30天';
        } else {
          _customStart = result.$1!;
          _customEnd = result.$2!;
          final presetName = matchPresetName(result.$1!, result.$2!);
          if (presetName != null) {
            _customPreset = presetName;
          } else {
            _customPreset =
                '${_formatDate(result.$1!)}~${_formatDate(result.$2!)}';
          }
        }
      });
      _loadData();
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
                if (_scrollController.hasClients) {
                  _scrollOffsets[_selectedRange] = _scrollController.offset;
                }
                _selectedIndexMap[_selectedRange] = _selectedIndex;
                _selectedRange = newRange;
                _selectedIndex = _selectedIndexMap[newRange] ?? _lastIndex;
                final cacheKey = StatsCacheKey(
                  range: _selectedRange,
                  index: _selectedIndex,
                  year: _selectedYear,
                  ledgerId: currentLedgerId.value,
                  customStart: _customStart,
                  customEnd: _customEnd,
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
                _restoreScrollPosition();
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
                    // 预构建全部标签：让 maxScrollExtent 一次到位（SliverList
                    // 对未构建项的估算偏小，跳“最新端”会跳不到真底）。
                    scrollCacheExtent: ScrollCacheExtent.pixels(10000),
                    padding: const EdgeInsets.symmetric(horizontal: spacingXS),
                    itemCount: _items.length,
                    separatorBuilder: (_, a) =>
                        const SizedBox(width: spacingXXS),
                    itemBuilder: (context, index) {
                      final isSelected = _selectedIndex == index;
                      return GestureDetector(
                        key: _itemKeys.putIfAbsent(index, GlobalKey.new),
                        onTap: () {
                          if (_selectedRange == StatsRange.custom) {
                            _showCustomDateFilter();
                          } else {
                            setState(() {
                              _selectedIndex = index;
                              _selectedIndexMap[_selectedRange] = index;
                            });
                            _loadData();
                            _scrollToSelected();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: spacingM,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _items[index],
                                style:
                                    isSelected &&
                                        _selectedRange != StatsRange.custom
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
                if (_selectedRange == StatsRange.week ||
                    _selectedRange == StatsRange.month) ...[
                  const SizedBox(width: spacingS),
                  GestureDetector(
                    onTap: _showYearPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: spacingM,
                        vertical: spacingXS,
                      ),
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
        builder: (_) =>
            StatsDetailPage(start: range.start, end: range.end, title: title),
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
        padding: const EdgeInsets.symmetric(
          horizontal: spacingM,
          vertical: spacingXS,
        ),
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

    final points = _periodData
        .map((e) => TrendPoint(label: e.label, value: e.amountCents))
        .toList();

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
      return CardContainer(title: '支出占比', child: const SizedBox.shrink());
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
      items: _expenseByCategory
          .map(
            (e) => RankingItem(
              name: e.categoryName,
              amountCents: e.amountCents,
              count: e.count,
            ),
          )
          .toList(),
    );
  }

  String get _periodTitle {
    switch (_selectedRange) {
      case StatsRange.week:
        return '周支出汇总';
      case StatsRange.month:
        return '月支出汇总';
      case StatsRange.year:
        return '年支出汇总';
      case StatsRange.custom:
        return '';
    }
  }

  Widget _buildPeriodSummary() {
    if (_selectedRange == StatsRange.custom) return const SizedBox.shrink();

    List<({String label, int amountCents})> summaryData;
    switch (_selectedRange) {
      case StatsRange.week:
        summaryData = _weekSummaryData;
        break;
      case StatsRange.month:
        summaryData = _monthSummaryData;
        break;
      case StatsRange.year:
        summaryData = _yearSummaryData;
        break;
      case StatsRange.custom:
        return const SizedBox.shrink();
    }

    if (summaryData.isEmpty) {
      return CardContainer(
        title: _periodTitle,
        child: const SizedBox(height: 160),
      );
    }

    final points = summaryData
        .map((e) => TrendPoint(label: e.label, value: e.amountCents))
        .toList();

    return CardContainer(
      title: _periodTitle,
      child: TrendLineChart(points: points),
    );
  }
}
