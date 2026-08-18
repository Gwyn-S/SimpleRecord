import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/asset_account.dart';
import '../services/asset_account_service.dart';
import '../services/theme_service.dart';
import '../utils/formatters.dart';
import '../widgets/account_avatar.dart';
import '../widgets/month_year_picker.dart';

/// 资产统计页面：资产/负债/净资产概览 + 走势图 + 余额占比 + 排行榜
class AssetStatisticsPage extends StatefulWidget {
  const AssetStatisticsPage({super.key});

  @override
  State<AssetStatisticsPage> createState() => _AssetStatisticsPageState();
}

class _AssetStatisticsPageState extends State<AssetStatisticsPage> {
  List<AssetAccount> _accounts = [];
  int _selectedType = 0; // 0=资产, 1=负债, 2=净资产
  int _selectedYear = DateTime.now().year; // 选中的年份

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    assetAccountsVersion.addListener(_loadAccounts);
  }

  @override
  void dispose() {
    assetAccountsVersion.removeListener(_loadAccounts);
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final accounts = await loadAssetAccounts();
    if (!mounted) return;
    setState(() => _accounts = accounts);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('资产统计'),
        backgroundColor: themeColor,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: colorBackgroundPage,
      body: _accounts.isEmpty
          ? const Center(child: Text('暂无资产数据', style: textHint))
          : ListView(
              padding: const EdgeInsets.all(spacingM),
              children: [
                _buildSummarySection(),
                const SizedBox(height: spacingM),
                _buildTrendCard(themeColor),
                if (_selectedType != 2) ...[
                  const SizedBox(height: spacingM),
                  _buildPieCard(),
                  const SizedBox(height: spacingM),
                  _buildRankingCard(),
                ],
              ],
            ),
    );
  }

  // ======================== 过滤后的数据 ========================

  /// 根据选中类型过滤后的账户列表
  List<AssetAccount> get _filteredAccounts {
    switch (_selectedType) {
      case 0: // 资产
        return _accounts.where((a) => !a.isDebtAccount).toList();
      case 1: // 负债
        return _accounts.where((a) => a.isDebtAccount).toList();
      default: // 净资产 - 全部
        return _accounts;
    }
  }

  /// 是否有数据
  bool get _hasData => _filteredAccounts.isNotEmpty;

  /// 根据选中类型过滤后的饼图数据
  List<_CategorySummary> get _filteredByCategory {
    final map = <String, int>{};
    for (final a in _filteredAccounts) {
      map[a.categoryName] = (map[a.categoryName] ?? 0) + a.balanceCents;
    }
    final list = map.entries
        .map((e) => _CategorySummary(
              name: e.key,
              amount: e.value.abs(),
              color: categoryColorByName(e.key),
            ))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  /// 根据选中类型过滤后的排行榜
  List<AssetAccount> get _filteredRanking {
    final sorted = List<AssetAccount>.from(_filteredAccounts)
      ..sort((a, b) => b.balanceCents.abs().compareTo(a.balanceCents.abs()));
    return sorted;
  }

  /// 根据选中类型过滤后的总金额
  int get _filteredTotal {
    return _filteredAccounts.fold(0, (s, a) => s + a.balanceCents.abs());
  }

  // ======================== 顶部概览：资产 / 负债 / 净资产 ========================

  Widget _buildSummarySection() {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Container(
      decoration: BoxDecoration(
        color: colorBackgroundCard,
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          _buildTab('资产', 0, themeColor),
          _buildTab('负债', 1, themeColor),
          _buildTab('净资产', 2, themeColor),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index, Color themeColor) {
    final isSelected = _selectedType == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          color: isSelected ? themeColor : Colors.transparent,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  // ======================== 走势图卡片 ========================

  String get _yearLabel {
    final now = DateTime.now().year;
    if (_selectedYear == now) return '今年';
    if (_selectedYear == now - 1) return '去年';
    if (_selectedYear == now - 2) return '前年';
    return '$_selectedYear';
  }

  Widget _buildTrendCard(Color themeColor) {
    return _CardContainer(
      title: '资产走势图',
      trailing: GestureDetector(
        onTap: _showYearPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorDivider,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _yearLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
      ),
      child: SizedBox(
        height: 180,
        child: _accounts.isEmpty
            ? const Center(child: Text('暂无数据', style: textHint))
            : _TrendLineChart(
                accounts: _filteredAccounts,
                themeColor: themeColor,
                showFlatZero: !_hasData,
              ),
      ),
    );
  }

  Future<void> _showYearPicker() async {
    final now = DateTime.now();
    final picked = await showYearPicker(
      context,
      DateTime(_selectedYear),
      maxYear: now.year, // 只能选当前年及之前
    );
    if (picked != null && mounted) {
      setState(() => _selectedYear = picked.year);
    }
  }

  // ======================== 资产余额占比（饼图） ========================

  Widget _buildPieCard() {
    final data = _filteredByCategory;
    final total = _filteredTotal;
    final title = _selectedType == 0
        ? '资产余额占比'
        : _selectedType == 1
            ? '负债余额占比'
            : '净资产占比';
    if (data.isEmpty) {
      return _CardContainer(
        title: title,
        child: const SizedBox.shrink(),
      );
    }
    return _CardContainer(
      title: title,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: SizedBox(
              height: 160,
              child: _AssetPieChart(data: data, total: total),
            ),
          ),
          Expanded(
            flex: 5,
            child: _PieLegend(data: data, total: total),
          ),
        ],
      ),
    );
  }

  // ======================== 排行榜 ========================

  Widget _buildRankingCard() {
    final ranking = _filteredRanking;
    final title = _selectedType == 0
        ? '资产排行榜'
        : _selectedType == 1
            ? '负债排行榜'
            : '净资产排行榜';
    if (ranking.isEmpty) {
      return _CardContainer(
        title: title,
        child: const SizedBox.shrink(),
      );
    }
    final totalAmount = _filteredTotal;
    return _CardContainer(
      title: title,
      child: Column(
        children: ranking.asMap().entries.map((entry) {
          final account = entry.value;
          final ratio = totalAmount > 0
              ? account.balanceCents.abs() / totalAmount
              : 0.0;
          return _RankingRow(
            account: account,
            ratio: ratio,
          );
        }).toList(),
      ),
    );
  }
}

// ======================================================================
//  子组件
// ======================================================================

/// 卡片容器
class _CardContainer extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _CardContainer({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(spacingL),
      decoration: BoxDecoration(
        color: colorBackgroundCard,
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: textTitleBold.copyWith(fontWeight: FontWeight.w500)),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: spacingM),
          child,
        ],
      ),
    );
  }
}

// ======================================================================
//  走势图（fl_chart LineChart）
// ======================================================================

class _TrendLineChart extends StatefulWidget {
  final List<AssetAccount> accounts;
  final Color themeColor;
  final bool showFlatZero;

  const _TrendLineChart({
    required this.accounts,
    required this.themeColor,
    this.showFlatZero = false,
  });

  @override
  State<_TrendLineChart> createState() => _TrendLineChartState();
}

class _TrendLineChartState extends State<_TrendLineChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentMonth = now.month;
    final accounts = widget.accounts;

    List<FlSpot> spots;
    if (widget.showFlatZero || accounts.isEmpty) {
      // 无数据时绘制平线
      spots = List.generate(
        currentMonth,
        (i) => FlSpot(i.toDouble(), 0),
      );
    } else {
      final total = accounts
          .where((a) => !a.isDebtAccount)
          .fold(0, (s, a) => s + a.balanceCents);
      final debt = accounts
          .where((a) => a.isDebtAccount)
          .fold(0, (s, a) => s + a.balanceCents.abs());
      final net = total - debt;

      // 生成数据（到当前月）
      // TODO: 接入真实历史月度余额快照数据，当前为占位随机值
      final rand = Random(42);
      spots = [];
      for (var i = 0; i < currentMonth - 1; i++) {
        final value = net * (0.8 + rand.nextDouble() * 0.4);
        spots.add(FlSpot(i.toDouble(), value));
      }
      spots.add(FlSpot((currentMonth - 1).toDouble(), net.toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final month = value.toInt() + 1;
                if (month >= 1 && month <= currentMonth) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('$month月', style: textItemSub.copyWith(fontSize: 10)),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (currentMonth - 1).toDouble(),
        minY: _minY(spots),
        maxY: _maxY(spots),
        showingTooltipIndicators: _touchedIndex != null
            ? [ShowingTooltipIndicators([
                LineBarSpot(
                  LineChartBarData(spots: spots),
                  0,
                  spots[_touchedIndex!],
                ),
              ])]
            : [],
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Colors.black,
            barWidth: 1.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: 4,
                color: Colors.white,
                strokeColor: Colors.black,
                strokeWidth: 1.5,
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: false,
          touchSpotThreshold: 40,
          distanceCalculator: (touchPoint, spotPixelCoordinates) =>
              (touchPoint.dx - spotPixelCoordinates.dx).abs(),
          touchCallback: (event, response) {
            if (event is FlTapUpEvent || event is FlLongPressEnd) {
              if (response?.lineBarSpots != null &&
                  response!.lineBarSpots!.isNotEmpty) {
                final idx = response.lineBarSpots!.first.spotIndex;
                setState(() {
                  _touchedIndex = _touchedIndex == idx ? null : idx;
                });
              }
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.black,
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final month = spot.x.toInt() + 1;
              return LineTooltipItem(
                '$month月\n${formatAmount(spot.y.toInt())}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  double _minY(List<FlSpot> spots) {
    if (spots.isEmpty) return 0;
    final minV = spots.map((s) => s.y).reduce(min);
    return minV == 0 ? -1 : minV * 0.9;
  }

  double _maxY(List<FlSpot> spots) {
    if (spots.isEmpty) return 1;
    final maxV = spots.map((s) => s.y).reduce(max);
    return maxV == 0 ? 1 : maxV * 1.1;
  }
}

// ======================================================================
//  饼图（fl_chart PieChart）
// ======================================================================

class _AssetPieChart extends StatelessWidget {
  final List<_CategorySummary> data;
  final int total;

  const _AssetPieChart({required this.data, required this.total});

  @override
  Widget build(BuildContext context) {
    return PieChart(
      PieChartData(
        sectionsSpace: 1,
        centerSpaceRadius: 32,
        sections: data.map((item) {
          final pct = total > 0 ? item.amount / total * 100 : 0.0;
          return PieChartSectionData(
            value: item.amount.toDouble(),
            color: item.color,
            title: '${pct.toStringAsFixed(1)}%',
            titleStyle: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            radius: 60,
          );
        }).toList(),
        pieTouchData: PieTouchData(
          touchCallback: (FlTouchEvent event, pieTouchResponse) {},
        ),
      ),
    );
  }
}

/// 饼图右侧图例
class _PieLegend extends StatelessWidget {
  final List<_CategorySummary> data;
  final int total;

  const _PieLegend({required this.data, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: spacingS),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: data.map((item) {
          final pct = total > 0 ? item.amount / total * 100 : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: spacingXXS),
                Expanded(
                  child: Text(
                    item.name,
                    style: textItemSub.copyWith(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: textItemSub.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ======================================================================
//  排行榜行
// ======================================================================

class _RankingRow extends StatelessWidget {
  final AssetAccount account;
  final double ratio;

  const _RankingRow({
    required this.account,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final percent = (ratio * 100).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: spacingXS),
      child: Column(
        children: [
          Row(
            children: [
              AccountAvatar(account: account, size: iconSizeSmall, color: themeColor),
              const SizedBox(width: spacingS),
              Expanded(
                child: Text(account.displayName, style: textListItem.copyWith(fontSize: 14)),
              ),
              Text(
                '$percent%',
                style: textItemSub.copyWith(fontSize: 12),
              ),
              const SizedBox(width: spacingS),
              Text(
                formatAmount(account.balanceCents),
                style: textAccountAmount.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: colorDivider,
              valueColor: AlwaysStoppedAnimation<Color>(themeColor),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
//  数据模型
// ======================================================================

class _CategorySummary {
  final String name;
  final int amount;
  final Color color;

  const _CategorySummary({
    required this.name,
    required this.amount,
    required this.color,
  });
}
