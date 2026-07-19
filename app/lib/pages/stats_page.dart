import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

// TODO: Phase 4 - 统计图表功能
// - 饼图：本月各分类支出占比
// - 折线图：近6个月收支趋势
// - 柱状图：各分类支出排行
// - 时间范围选择（本月/近3月/近6月/本年）
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('暂无数据', style: TextStyle(fontSize: 14, color: colorTextPlaceholder)),
    );
  }
}
