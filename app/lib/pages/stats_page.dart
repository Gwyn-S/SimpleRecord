import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/record_service.dart';
import '../services/theme_service.dart';
import '../utils/formatters.dart';
import '../widgets/card_container.dart';
import '../widgets/date_filter_sheet.dart';
import '../widgets/month_year_picker.dart';
import '../widgets/tab_bar.dart';
import '../widgets/tab_switcher_app_bar.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _isExpense = true;
  int _selectedRange = 1; // 0=周 1=月 2=年 3=自定义
  late int _selectedIndex;
  int _selectedYear = DateTime.now().year;
  final ScrollController _scrollController = ScrollController();
  final Map<int, int> _selectedIndexMap = {};
  String _customPreset = '最近30天';
  DateTime? _customStart;
  DateTime? _customEnd;

  // 数据状态
  int _totalExpense = 0;
  int _totalIncome = 0;
  List<({String categoryName, int amountCents})> _expenseByCategory = [];
  List<({String label, int amountCents})> _periodData = [];

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
      _scrollToEnd();
      _loadData();
    });
  }

  void _scrollToEnd() {
    if (_scrollController.hasClients) {
      // 等待布局完成后再滚动
      Future.delayed(Duration.zero, () {
        if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  /// 根据当前选中的 tab 和 index 计算日期范围
  ({DateTime start, DateTime end})? _getDateRange() {
    final now = DateTime.now();
    switch (_selectedRange) {
      case 0: // 周
        final startOfYear = DateTime(now.year, 1, 1);
        final currentWeek = ((now.difference(startOfYear).inDays + startOfYear.weekday) / 7).ceil();
        final totalItems = _items.length;
        final weekOffset = totalItems - 1 - _selectedIndex;
        final targetWeek = currentWeek - weekOffset;
        final weekStart = startOfYear.add(Duration(days: (targetWeek - 1) * 7));
        final weekEnd = weekStart.add(const Duration(days: 7));
        return (start: weekStart, end: weekEnd);
      case 1: // 月
        final monthOffset = _items.length - 1 - _selectedIndex;
        final targetMonth = now.month - monthOffset;
        final targetYear = _selectedYear;
        final start = DateTime(targetYear, targetMonth, 1);
        final end = DateTime(targetYear, targetMonth + 1, 1);
        return (start: start, end: end);
      case 2: // 年
        final yearOffset = _items.length - 1 - _selectedIndex;
        final targetYear = _selectedYear - yearOffset;
        final start = DateTime(targetYear, 1, 1);
        final end = DateTime(targetYear + 1, 1, 1);
        return (start: start, end: end);
      case 3: // 自定义
        if (_customStart != null && _customEnd != null) {
          return (start: _customStart!, end: _customEnd!);
        }
        return null;
      default:
        return null;
    }
  }

  Future<void> _loadData() async {
    final range = _getDateRange();
    if (range == null) return;
    final ledgerId = currentLedgerId.value;
    
    final records = await loadRecordsByDateRange(
      ledgerId: ledgerId,
      start: range.start,
      end: range.end,
    );
    
    final expenseByCategory = await loadExpenseByCategory(
      ledgerId: ledgerId,
      start: range.start,
      end: range.end,
    );
    
    if (!mounted) return;
    
    int totalExpense = 0;
    int totalIncome = 0;
    for (final r in records) {
      if (r.isExpense) {
        totalExpense += r.amountCents;
      } else {
        totalIncome += r.amountCents;
      }
    }
    
    // 加载周期数据
    final periodData = await _loadPeriodData();
    
    setState(() {
      _totalExpense = totalExpense;
      _totalIncome = totalIncome;
      _expenseByCategory = expenseByCategory;
      _periodData = periodData;
    });
  }

  Future<List<({String label, int amountCents})>> _loadPeriodData() async {
    final ledgerId = currentLedgerId.value;
    
    switch (_selectedRange) {
      case 0: // 周：显示本周每天的支出
        final range = _getDateRange();
        if (range == null) return [];
        final records = await loadRecordsByDateRange(
          ledgerId: ledgerId,
          start: range.start,
          end: range.end,
        );
        final dailyExpense = List.filled(7, 0);
        final dayLabels = ['一', '二', '三', '四', '五', '六', '日'];
        for (final r in records) {
          if (!r.isExpense) continue;
          final dayIndex = (r.date.weekday - 1) % 7;
          dailyExpense[dayIndex] += r.amountCents;
        }
        return List.generate(7, (i) => (
          label: dayLabels[i],
          amountCents: dailyExpense[i],
        ));
      
      case 1: // 月：显示本月每周的支出
        final range = _getDateRange();
        if (range == null) return [];
        final records = await loadRecordsByDateRange(
          ledgerId: ledgerId,
          start: range.start,
          end: range.end,
        );
        // 计算本月有几周
        final firstDay = range.start;
        final lastDay = range.end.subtract(const Duration(days: 1));
        final firstWeekStart = firstDay.subtract(Duration(days: firstDay.weekday - 1));
        final lastWeekEnd = lastDay.add(Duration(days: 7 - lastDay.weekday));
        final totalWeeks = ((lastWeekEnd.difference(firstWeekStart).inDays) / 7).ceil();
        final weeklyExpense = List.filled(totalWeeks, 0);
        for (final r in records) {
          if (!r.isExpense) continue;
          final weekIndex = ((r.date.difference(firstWeekStart).inDays) / 7).floor();
          if (weekIndex >= 0 && weekIndex < totalWeeks) {
            weeklyExpense[weekIndex] += r.amountCents;
          }
        }
        return List.generate(totalWeeks, (i) => (
          label: '第${i + 1}周',
          amountCents: weeklyExpense[i],
        ));
      
      case 2: // 年：显示今年每月的支出
        final year = _selectedYear;
        final monthlyExpense = List.filled(12, 0);
        final allRecords = await loadRecordsByDateRange(
          ledgerId: ledgerId,
          start: DateTime(year, 1, 1),
          end: DateTime(year + 1, 1, 1),
        );
        for (final r in allRecords) {
          if (!r.isExpense) continue;
          final monthIndex = r.date.month - 1;
          monthlyExpense[monthIndex] += r.amountCents;
        }
        return List.generate(12, (i) => (
          label: '${i + 1}月',
          amountCents: monthlyExpense[i],
        ));
      
      case 3: // 自定义：显示每天的支出
        if (_customStart == null || _customEnd == null) return [];
        final records = await loadRecordsByDateRange(
          ledgerId: ledgerId,
          start: _customStart!,
          end: _customEnd!,
        );
        final days = _customEnd!.difference(_customStart!).inDays;
        if (days <= 0) return [];
        final dailyExpense = List.filled(days, 0);
        for (final r in records) {
          if (!r.isExpense) continue;
          final dayIndex = r.date.difference(_customStart!).inDays;
          if (dayIndex >= 0 && dayIndex < days) {
            dailyExpense[dayIndex] += r.amountCents;
          }
        }
        return List.generate(days, (i) => (
          label: '第${i + 1}天',
          amountCents: dailyExpense[i],
        ));
      
      default:
        return [];
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<String> get _items {
    final now = DateTime.now();
    switch (_selectedRange) {
      case 0: // 周：1周 2周 3周... 上周 本周
        final startOfYear = DateTime(now.year, 1, 1);
        final currentWeek = ((now.difference(startOfYear).inDays + startOfYear.weekday) / 7).ceil();
        return [
          for (var i = 1; i <= currentWeek - 1; i++) '$i周',
          '上周',
          '本周',
        ];
      case 1: // 月：1月 2月... 上月 本月
        return [
          for (var i = 1; i <= now.month - 1; i++) '$i月',
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
        _customStart = result.$1;
        _customEnd = result.$2;
        if (result.$1 == null && result.$2 == null) {
          _customPreset = '日期不限';
        } else if (result.$1 != null && result.$2 != null) {
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
                // 保存当前tab的选择
                _selectedIndexMap[_selectedRange] = _selectedIndex;
                setState(() {
                  _selectedRange = i;
                  // 恢复目标tab的选择，如果没有则选最后一项
                  _selectedIndex = _selectedIndexMap[i] ?? _lastIndex;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToEnd();
                  _loadData();
                });
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
          const SizedBox(height: spacingM),
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
      trailing: _buildTrailingButton('详情'),
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

  Widget _buildTrailingButton(String label) {
    return GestureDetector(
      onTap: () {},
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
    // TODO: 假数据，后续替换为真实柱状图
    final fakeData = [3200, 2800, 4100, 3600, 2900, 3800, 2580];
    final labels = ['一', '二', '三', '四', '五', '六', '日'];
    final maxVal = fakeData.reduce((a, b) => a > b ? a : b).toDouble();

    return CardContainer(
      title: '支出统计',
      trailing: _buildTrailingButton('详情'),
      child: SizedBox(
        height: 160,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(fakeData.length, (i) {
            final ratio = fakeData[i] / maxVal;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: spacingXXS),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(formatAmount(fakeData[i]), style: textChartLabel),
                    const SizedBox(height: spacingXXS),
                    Container(
                      height: 100 * ratio,
                      decoration: BoxDecoration(
                        color: colorExpense,
                        borderRadius: BorderRadius.circular(radiusTiny),
                      ),
                    ),
                    const SizedBox(height: spacingXXS),
                    Text(labels[i], style: textChartLabel),
                  ],
                ),
              ),
            );
          }),
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
    final colors = [colorExpense, colorIncome, colorTextSecondary, colorDivider, colorTextPlaceholder];

    return CardContainer(
      title: '支出占比',
      child: Column(
        children: List.generate(_expenseByCategory.length, (i) {
          final item = _expenseByCategory[i];
          final ratio = item.amountCents / total;
          final color = colors[i % colors.length];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: spacingXS),
            child: Row(
              children: [
                Container(width: 12, height: 12, color: color),
                const SizedBox(width: spacingS),
                SizedBox(width: 50, child: Text(item.categoryName, style: textBody)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radiusTiny),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 12,
                      backgroundColor: colorDivider,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
                const SizedBox(width: spacingS),
                Text('${(ratio * 100).toStringAsFixed(1)}%', style: textItemSub),
              ],
            ),
          );
        }),
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

    final icons = {
      '餐饮': Icons.restaurant,
      '购物': Icons.shopping_bag,
      '交通': Icons.directions_car,
      '娱乐': Icons.sports_esports,
    };

    return CardContainer(
      title: '支出排行',
      child: Column(
        children: List.generate(_expenseByCategory.length, (i) {
          final item = _expenseByCategory[i];
          final icon = icons[item.categoryName] ?? Icons.category;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: spacingXS),
            child: Row(
              children: [
                Text('${i + 1}', style: textBody),
                const SizedBox(width: spacingM),
                Icon(icon, size: iconSizeSmall, color: colorTextSecondary),
                const SizedBox(width: spacingM),
                Expanded(child: Text(item.categoryName, style: textBody)),
                Text(formatAmount(item.amountCents), style: textAmountFlow),
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
      case 0: return '本周支出';
      case 1: return '$_selectedYear年${_items[_selectedIndex]}支出';
      case 2: return '$_selectedYear年月支出汇总';
      case 3: return '自定义支出';
      default: return '支出汇总';
    }
  }

  Widget _buildPeriodSummary() {
    if (_periodData.isEmpty) {
      return CardContainer(
        title: _periodTitle,
        trailing: _buildTrailingButton('详情'),
        child: const Center(
          child: Text('暂无数据', style: textHint),
        ),
      );
    }

    final maxVal = _periodData.map((e) => e.amountCents).reduce((a, b) => a > b ? a : b).toDouble();

    return CardContainer(
      title: _periodTitle,
      trailing: _buildTrailingButton('详情'),
      child: Column(
        children: _periodData.map((item) {
          final ratio = maxVal > 0 ? item.amountCents / maxVal : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: spacingXS),
            child: Row(
              children: [
                SizedBox(width: 50, child: Text(item.label, style: textBody)),
                const SizedBox(width: spacingM),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radiusTiny),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 12,
                      backgroundColor: colorDivider,
                      valueColor: AlwaysStoppedAnimation(colorExpense),
                    ),
                  ),
                ),
                const SizedBox(width: spacingS),
                Text(formatAmount(item.amountCents), style: textItemSub),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
