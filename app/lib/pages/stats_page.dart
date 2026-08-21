import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
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
  int _selectedIndex = 0;

  static const _rangeLabels = ['周', '月', '年', '自定义'];

  List<String> get _items {
    final now = DateTime.now();
    switch (_selectedRange) {
      case 0: // 周
        return List.generate(54, (i) {
          if (i == 0) return '本周';
          return '$i周前';
        });
      case 1: // 月
        return List.generate(now.month, (i) {
          final m = now.month - i;
          return '$m月';
        });
      case 2: // 年
        return List.generate(now.year - 1999, (i) {
          final y = now.year - i;
          if (i == 0) return '今年';
          if (i == 1) return '去年';
          if (i == 2) return '前年';
          return '$y年';
        });
      case 3: // 自定义
        return ['选择日期范围'];
      default:
        return [];
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
              selectedIndex: _selectedRange,
              onChanged: (i) => setState(() {
                _selectedRange = i;
                _selectedIndex = 0;
              }),
            ),
          ),
          const SizedBox(height: spacingM),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: spacingXS),
              itemCount: _items.length,
              separatorBuilder: (_, a) => const SizedBox(width: spacingS),
              itemBuilder: (context, index) {
                final isSelected = _selectedIndex == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: spacingM),
                    decoration: BoxDecoration(
                      color: isSelected ? themeColor : colorBackgroundCard,
                      borderRadius: BorderRadius.circular(radiusSmall),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _items[index],
                      style: isSelected
                          ? textTagSmall.copyWith(color: colorTextOnPrimary)
                          : textTagSmall,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
