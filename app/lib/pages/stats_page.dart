import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<String> get _items {
    final now = DateTime.now();
    switch (_selectedRange) {
      case 0: // 周：1周 2周 3周... 上周 本周
        final now = DateTime.now();
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
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
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
        ],
      ),
    );
  }
}
