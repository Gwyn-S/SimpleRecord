import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/category.dart';
import '../models/record.dart';
import '../services/record_service.dart';
import '../services/theme_service.dart';
import '../utils/formatters.dart';
import '../widgets/card_container.dart';
import '../widgets/date_filter_sheet.dart';
import '../widgets/donut_pie_chart.dart';
import '../widgets/month_year_picker.dart';
import '../widgets/tab_bar.dart';
import '../widgets/tab_switcher_app_bar.dart';
import 'stats_detail_page.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _isExpense = true;
  int _selectedRange = 0; // 0=周 1=月 2=年 3=自定义
  late int _selectedIndex;
  int _selectedYear = DateTime.now().year;
  final ScrollController _scrollController = ScrollController();
  final Map<int, int> _selectedIndexMap = {};
  String _customPreset = '最近30天';
  late DateTime _customStart = DateTime.now().subtract(const Duration(days: 30));
  late DateTime _customEnd = DateTime.now();

  // 数据状态
  int _totalExpense = 0;
  int _totalIncome = 0;
  List<({String categoryName, int amountCents, int count})> _expenseByCategory = [];
  List<({String label, int amountCents})> _periodData = [];
  List<({String label, int amountCents})> _weekSummaryData = [];
  List<({String label, int amountCents})> _monthSummaryData = [];
  List<({String label, int amountCents})> _yearSummaryData = [];
  final Map<String, ({int expense, int income, List<({String categoryName, int amountCents, int count})> categories, List<({String label, int amountCents})> period, List<({String label, int amountCents})> weekSummary, List<({String label, int amountCents})> monthSummary, List<({String label, int amountCents})> yearSummary})> _dataCache = {};

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
    final now = DateTime.now();
    switch (_selectedRange) {
      case 0: // 周
        final jan1 = DateTime(now.year, 1, 1);
        final jan1Monday = jan1.subtract(Duration(days: jan1.weekday - 1));
        final currentMonday = now.subtract(Duration(days: now.weekday - 1));
        final currentWeek = ((currentMonday.difference(jan1Monday).inDays) / 7).floor() + 1;
        final totalItems = _items.length;
        final weekOffset = totalItems - 1 - _selectedIndex;
        final targetWeek = currentWeek - weekOffset;
        final weekStart = jan1Monday.add(Duration(days: (targetWeek - 1) * 7));
        final weekEnd = weekStart.add(const Duration(days: 7));
        return (start: weekStart, end: weekEnd);
      case 1: // 月
        final monthOffset = _items.length - 1 - _selectedIndex;
        final targetMonth = now.month - monthOffset;
        final targetYear = _selectedYear;
        final start = DateTime(targetYear, targetMonth, 1);
        final end = DateTime(targetYear, targetMonth + 1, 0); // 月末
        return (start: start, end: end);
      case 2: // 年
        final yearOffset = _items.length - 1 - _selectedIndex;
        final targetYear = _selectedYear - yearOffset;
        final start = DateTime(targetYear, 1, 1);
        final end = DateTime(targetYear + 1, 1, 1);
        return (start: start, end: end);
      case 3: // 自定义
        return (start: _customStart, end: _customEnd);
      default:
        return null;
    }
  }

  Future<void> _loadData() async {
    final range = _getDateRange();
    if (range == null) return;
    final ledgerId = currentLedgerId.value;
    if (ledgerId == null) return;
    
    try {
      // 周/月 tab 需要全年数据来计算汇总
      final loadStart = (_selectedRange == 0 || _selectedRange == 1)
          ? DateTime(_selectedYear, 1, 1)
          : _selectedRange == 2
              ? DateTime(_selectedYear - 5, 1, 1)
              : range.start;
      final loadEnd = (_selectedRange == 0 || _selectedRange == 1)
          ? DateTime(_selectedYear + 1, 1, 1)
          : _selectedRange == 2
              ? DateTime(_selectedYear + 1, 1, 1)
              : range.end;

      final results = await Future.wait([
        loadRecordsByDateRange(
          ledgerId: ledgerId,
          start: loadStart,
          end: loadEnd,
        ),
        loadExpenseByCategory(
          ledgerId: ledgerId,
          start: _selectedRange == 0 ? range.start : range.start,
          end: _selectedRange == 0 ? range.end : range.end,
        ),
      ]);
      
      if (!mounted) return;
      
      final records = results[0] as List<Record>;
      final expenseByCategory = results[1] as List<({String categoryName, int amountCents, int count})>;
      
      int totalExpense = 0;
      int totalIncome = 0;
      for (final r in records) {
        if (r.isExpense) {
          totalExpense += r.amountCents;
        } else {
          totalIncome += r.amountCents;
        }
      }
      
      final periodData = _buildPeriodData(records);
      final weekSummaryData = _buildWeekSummaryData(records);
      final monthSummaryData = _buildMonthSummaryData(records);
      final yearSummaryData = _buildYearSummaryData(records);
      
      setState(() {
        _totalExpense = totalExpense;
        _totalIncome = totalIncome;
        _expenseByCategory = expenseByCategory;
        _periodData = periodData;
        _weekSummaryData = weekSummaryData;
        _monthSummaryData = monthSummaryData;
        _yearSummaryData = yearSummaryData;
      });
      final cacheKey = '$_selectedRange-$_selectedIndex';
      _dataCache[cacheKey] = (
        expense: totalExpense,
        income: totalIncome,
        categories: expenseByCategory,
        period: periodData,
        weekSummary: weekSummaryData,
        monthSummary: monthSummaryData,
        yearSummary: yearSummaryData,
      );
    } catch (e) {
      // 加载失败，保持当前状态
    }
  }

  List<({String label, int amountCents})> _buildPeriodData(List<Record> records) {
    switch (_selectedRange) {
      case 0: // 周：显示本周每天的支出（供支出统计图）
        final range = _getDateRange();
        if (range == null) return [];
        final days = range.end.difference(range.start).inDays;
        final dailyExpense = List.filled(days, 0);
        for (final r in records) {
          if (!r.isExpense) continue;
          final dayIndex = r.date.difference(range.start).inDays;
          if (dayIndex >= 0 && dayIndex < days) {
            dailyExpense[dayIndex] += r.amountCents;
          }
        }
        return List.generate(days, (i) {
          final date = range.start.add(Duration(days: i));
          return (
            label: '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
            amountCents: dailyExpense[i],
          );
        });
      
      case 1: // 月：显示本月每天的支出
        final range = _getDateRange();
        if (range == null) return [];
        final days = range.end.difference(range.start).inDays + 1;
        final dailyExpense = List.filled(days, 0);
        for (final r in records) {
          if (!r.isExpense) continue;
          final dayIndex = r.date.difference(range.start).inDays;
          if (dayIndex >= 0 && dayIndex < days) {
            dailyExpense[dayIndex] += r.amountCents;
          }
        }
        return List.generate(days, (i) {
          final date = range.start.add(Duration(days: i));
          return (
            label: date.day.toString().padLeft(2, '0'),
            amountCents: dailyExpense[i],
          );
        });
      
      case 2: // 年：显示今年每天的支出
        final range = _getDateRange();
        if (range == null) return [];
        final days = range.end.difference(range.start).inDays;
        final dailyExpense = List.filled(days, 0);
        for (final r in records) {
          if (!r.isExpense) continue;
          final dayIndex = r.date.difference(range.start).inDays;
          if (dayIndex >= 0 && dayIndex < days) {
            dailyExpense[dayIndex] += r.amountCents;
          }
        }
        return List.generate(days, (i) {
          final date = range.start.add(Duration(days: i));
          return (
            label: '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
            amountCents: dailyExpense[i],
          );
        });
      
      case 3: // 自定义：显示每天的支出
        final days = _customEnd.difference(_customStart).inDays;
        if (days <= 0) return [];
        final dailyExpense = List.filled(days, 0);
        for (final r in records) {
          if (!r.isExpense) continue;
          final dayIndex = r.date.difference(_customStart).inDays;
          if (dayIndex >= 0 && dayIndex < days) {
            dailyExpense[dayIndex] += r.amountCents;
          }
        }
        return List.generate(days, (i) {
          final date = _customStart.add(Duration(days: i));
          return (
            label: '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
            amountCents: dailyExpense[i],
          );
        });
      
      default:
        return [];
    }
  }

  List<({String label, int amountCents})> _buildWeekSummaryData(List<Record> records) {
    final now = DateTime.now();
    final jan1 = DateTime(now.year, 1, 1);
    final jan1Monday = jan1.subtract(Duration(days: jan1.weekday - 1));
    final currentMonday = now.subtract(Duration(days: now.weekday - 1));
    final currentWeek = ((currentMonday.difference(jan1Monday).inDays) / 7).floor() + 1;
    final weeklyExpense = List.filled(currentWeek, 0);
    for (final r in records) {
      if (!r.isExpense) continue;
      final rMonday = DateTime(r.date.year, r.date.month, r.date.day).subtract(Duration(days: r.date.weekday - 1));
      final weekIndex = ((rMonday.difference(jan1Monday).inDays) / 7).floor();
      if (weekIndex >= 0 && weekIndex < currentWeek) {
        weeklyExpense[weekIndex] += r.amountCents;
      }
    }
    return List.generate(currentWeek, (i) {
      final isLastWeek = i == currentWeek - 2;
      final isThisWeek = i == currentWeek - 1;
      final label = isThisWeek ? '本周' : isLastWeek ? '上周' : '${i + 1}周';
      return (label: label, amountCents: weeklyExpense[i]);
    });
  }

  List<({String label, int amountCents})> _buildMonthSummaryData(List<Record> records) {
    final now = DateTime.now();
    final monthlyExpense = List.filled(now.month, 0);
    for (final r in records) {
      if (!r.isExpense) continue;
      final monthIndex = r.date.month - 1;
      if (monthIndex >= 0 && monthIndex < now.month) {
        monthlyExpense[monthIndex] += r.amountCents;
      }
    }
    return List.generate(now.month, (i) {
      final isLastMonth = i == now.month - 2;
      final isThisMonth = i == now.month - 1;
      final label = isThisMonth ? '本月' : isLastMonth ? '上月' : '${i + 1}月';
      return (label: label, amountCents: monthlyExpense[i]);
    });
  }

  List<({String label, int amountCents})> _buildYearSummaryData(List<Record> records) {
    final now = DateTime.now();
    final startYear = now.year - 5;
    final yearCount = 6;
    final yearlyExpense = List.filled(yearCount, 0);
    for (final r in records) {
      if (!r.isExpense) continue;
      final yearIndex = r.date.year - startYear;
      if (yearIndex >= 0 && yearIndex < yearCount) {
        yearlyExpense[yearIndex] += r.amountCents;
      }
    }
    return List.generate(yearCount, (i) {
      final year = startYear + i;
      final label = year == now.year ? '今年' : year == now.year - 1 ? '去年' : year == now.year - 2 ? '前年' : '$year';
      return (label: label, amountCents: yearlyExpense[i]);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<String> get _items {
    final now = DateTime.now();
    switch (_selectedRange) {
      case 0: // 周：按周一~周日计算
        final thisMonday = DateTime(now.year, 1, 1);
        // 找到1月1日所在周的周一
        final jan1Monday = thisMonday.subtract(Duration(days: thisMonday.weekday - 1));
        final currentMonday = now.subtract(Duration(days: now.weekday - 1));
        final currentWeek = ((currentMonday.difference(jan1Monday).inDays) / 7).floor() + 1;
        return [
          for (var i = 1; i <= currentWeek - 1; i++) '$i周',
          '上周',
          '本周',
        ];
      case 1: // 月：1月 2月... 上月 本月
        return [
          for (var i = 1; i <= now.month - 2; i++) '$i月',
          '上月',
          '本月',
        ];
      case 2: // 年：(今年-5) (今年-4) (今年-3) 前年 去年 今年
        final y = now.year;
        return [
          '${y - 5}',
          '${y - 4}',
          '${y - 3}',
          '前年',
          '去年',
          '今年',
        ];
      case 3: // 自定义
        return [_customPreset];
      default:
        return [];
    }
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
      builder: (context) => DateFilterSheet(
        initialStart: _customStart,
        initialEnd: _customEnd,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (result.$1 == null || result.$2 == null) {
          // 用户选择"不限"，保持默认最近30天
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
            _customPreset = '${_formatDate(result.$1!)}~${_formatDate(result.$2!)}';
          }
        }
      });
      _loadData();
    }
  }

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
              selectedIndex: _selectedRange,
              onChanged: (i) {
                _selectedIndexMap[_selectedRange] = _selectedIndex;
                _selectedRange = i;
                _selectedIndex = _selectedIndexMap[i] ?? _lastIndex;
                // 立即用缓存数据渲染
                final cacheKey = '$_selectedRange-$_selectedIndex';
                final cached = _dataCache[cacheKey];
                setState(() {
                  if (cached != null) {
                    _totalExpense = cached.expense;
                    _totalIncome = cached.income;
                    _expenseByCategory = cached.categories;
                    _periodData = cached.period;
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
                          if (_selectedRange == 3) {
                            // 自定义tab，点击打开日期筛选
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
                                style: isSelected && _selectedRange != 3
                                    ? textTagSmall.copyWith(color: themeColor)
                                    : textTagSmall,
                              ),
                              if (_selectedRange == 3) ...[
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
                if (_selectedRange == 0 || _selectedRange == 1) ...[
                  const SizedBox(width: spacingS),
                  GestureDetector(
                    onTap: _showYearPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: spacingM, vertical: spacingXS),
                      decoration: BoxDecoration(
                        color: colorBackgroundCard,
                        borderRadius: BorderRadius.circular(radiusSmall),
                      ),
                      child: Text(
                        _yearLabel,
                        style: textTagSmall,
                      ),
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

  // ======================== 收支统计卡片 ========================

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
        Text(
          formatAmount(amountCents),
          style: textAmountSummary,
        ),
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

  // ======================== 支出统计图 ========================

  Widget _buildTrendChart() {
    if (_periodData.isEmpty) {
      return CardContainer(
        title: '支出统计图',
        trailing: _buildTrailingButton('详情', onTap: _openDetail),
        child: const SizedBox(
          height: 160,
          child: Center(
            child: Text('暂无数据', style: textHint),
          ),
        ),
      );
    }

    final points = _periodData.map((e) => _TrendPoint(
      label: e.label,
      value: e.amountCents,
    )).toList();

    final values = _periodData.map((e) => e.amountCents.toDouble()).toList();
    final minY = values.isEmpty ? -1.0 : values.reduce((a, b) => a < b ? a : b) * 0.9;
    final maxY = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b) * 1.1;

    final tooltip = TooltipBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      tooltipPosition: TooltipPosition.pointer,
      animationDuration: 0,
      builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
        final p = points[pointIndex];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${p.label} ${formatAmount(p.value)}',
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        );
      },
    );

    // 根据数据量决定X轴标签显示间隔
    final interval = points.length > 31 ? (points.length / 10).ceil() : 1;

    return CardContainer(
      title: '支出统计图',
      trailing: _buildTrailingButton('详情', onTap: _openDetail),
      child: SizedBox(
        height: 160,
        child: SfCartesianChart(
          margin: const EdgeInsets.all(0),
          plotAreaBorderWidth: 0,
          primaryXAxis: CategoryAxis(
            majorGridLines: const MajorGridLines(width: 0),
            majorTickLines: const MajorTickLines(size: 0),
            axisLine: const AxisLine(width: 0),
            labelStyle: textChartLabel,
            labelRotation: points.length > 31 ? -45 : 0,
            interval: interval.toDouble(),
          ),
          primaryYAxis: NumericAxis(
            minimum: minY,
            maximum: maxY,
            isVisible: false,
          ),
          tooltipBehavior: tooltip,
          series: <LineSeries<_TrendPoint, String>>[
            LineSeries<_TrendPoint, String>(
              dataSource: points,
              xValueMapper: (point, _) => point.label,
              yValueMapper: (point, _) => point.value,
              color: colorTextPrimary,
              width: 1.5,
              markerSettings: MarkerSettings(
                isVisible: _selectedRange != 2,
                shape: DataMarkerType.circle,
                height: 3,
                width: 3,
                borderWidth: 1.5,
                borderColor: colorTextPrimary,
                color: colorTextOnPrimary,
              ),
              animationDuration: 0,
            ),
          ],
        ),
      ),
    );
  }

  // ======================== 支出占比 ========================

  Widget _buildPieChart() {
    if (_expenseByCategory.isEmpty) {
      return CardContainer(
        title: '支出占比',
        child: const Center(
          child: Text('暂无数据', style: textHint),
        ),
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

  // ======================== 支出排行榜 ========================

  Widget _buildRankingCard() {
    if (_expenseByCategory.isEmpty) {
      return CardContainer(
        title: '支出排行',
        child: const Center(
          child: Text('暂无数据', style: textHint),
        ),
      );
    }

    final totalExpense = _expenseByCategory.fold(0, (s, e) => s + e.amountCents);
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;

    return CardContainer(
      title: '支出排行',
      child: Column(
        children: List.generate(_expenseByCategory.length, (i) {
          final item = _expenseByCategory[i];
          final ratio = totalExpense > 0 ? (item.amountCents / totalExpense).clamp(0.0, 1.0) : 0.0;
          final percent = (ratio * 100).toStringAsFixed(2);
          final category = expenseCategories.firstWhere(
            (c) => c.name == item.categoryName,
            orElse: () => Category(icon: Icons.category, name: item.categoryName),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: sizeCategoryCircle,
                  height: sizeCategoryCircle,
                  decoration: const BoxDecoration(
                    color: colorIconLightBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    category.icon,
                    size: iconSizeXLarge,
                    color: colorIconGray,
                  ),
                ),
                const SizedBox(width: spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(item.categoryName, style: textBody),
                          const SizedBox(width: spacingM),
                          Text('$percent%', style: textBody.copyWith(color: colorTextPrimary)),
                          const Spacer(),
                          Text('(共${item.count}笔)', style: textItemSub.copyWith(color: colorTextHint)),
                          const SizedBox(width: spacingXS),
                          Text(formatAmount(item.amountCents), style: textAmountFlow),
                        ],
                      ),
                      const SizedBox(height: spacingS),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: colorDivider,
                          valueColor: AlwaysStoppedAnimation(themeColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ======================== 今年周支出汇总 ========================

  String get _periodTitle {
    switch (_selectedRange) {
      case 0: return '$_selectedYear年周支出汇总';
      case 1: return '$_selectedYear年月支出汇总';
      case 2: return '$_selectedYear年年支出汇总';
      default: return '';
    }
  }

  Widget _buildPeriodSummary() {
    if (_selectedRange == 3) return const SizedBox.shrink();

    List<({String label, int amountCents})> summaryData;
    switch (_selectedRange) {
      case 0: summaryData = _weekSummaryData; break;
      case 1: summaryData = _monthSummaryData; break;
      case 2: summaryData = _yearSummaryData; break;
      default: return const SizedBox.shrink();
    }

    if (summaryData.isEmpty) {
      return CardContainer(
        title: _periodTitle,
        child: const Center(
          child: Text('暂无数据', style: textHint),
        ),
      );
    }

    return CardContainer(
      title: _periodTitle,
      child: SizedBox(
        height: 160,
        child: _buildLineChart(summaryData),
      ),
    );
  }

  Widget _buildLineChart(List<({String label, int amountCents})> data) {
    final points = data.map((e) => _TrendPoint(label: e.label, value: e.amountCents)).toList();
    final values = points.map((p) => p.value.toDouble()).toList();
    final minY = values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxY = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final tooltip = TooltipBehavior(enable: true, animationDuration: 0, header: '', canShowMarker: false);
    final interval = points.length > 31 ? (points.length / 10).ceil() : 1;

    return SfCartesianChart(
      margin: const EdgeInsets.all(0),
      plotAreaBorderWidth: 0,
      primaryXAxis: CategoryAxis(
        majorGridLines: const MajorGridLines(width: 0),
        majorTickLines: const MajorTickLines(size: 0),
        axisLine: const AxisLine(width: 0),
        labelStyle: textChartLabel,
        labelRotation: points.length > 12 ? -45 : 0,
        interval: interval.toDouble(),
      ),
      primaryYAxis: NumericAxis(
        minimum: minY,
        maximum: maxY,
        isVisible: false,
      ),
      tooltipBehavior: tooltip,
      series: <LineSeries<_TrendPoint, String>>[
        LineSeries<_TrendPoint, String>(
          dataSource: points,
          xValueMapper: (point, _) => point.label,
          yValueMapper: (point, _) => point.value,
          color: colorTextPrimary,
          width: 1.5,
          markerSettings: MarkerSettings(
            isVisible: true,
            shape: DataMarkerType.circle,
            height: 3,
            width: 3,
            borderWidth: 1.5,
            borderColor: colorTextPrimary,
            color: colorTextOnPrimary,
          ),
          animationDuration: 0,
        ),
      ],
    );
  }
}

class _TrendPoint {
  final String label;
  final int value;
  const _TrendPoint({required this.label, required this.value});
}
