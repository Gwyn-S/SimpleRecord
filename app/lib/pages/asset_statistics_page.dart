import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
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

  // 预算缓存，避免 build 时重复计算
  List<AssetAccount> _filteredAccounts = [];
  List<_CategorySummary> _filteredByCategory = [];
  List<AssetAccount> _filteredRanking = [];
  int _filteredTotal = 0;

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
    _accounts = accounts;
    _recompute();
    setState(() {});
  }

  void _recompute() {
    switch (_selectedType) {
      case 0:
        _filteredAccounts = _accounts.where((a) => !a.isDebtAccount).toList();
      case 1:
        _filteredAccounts = _accounts.where((a) => a.isDebtAccount).toList();
      default:
        _filteredAccounts = _accounts;
    }

    final map = <String, int>{};
    for (final a in _filteredAccounts) {
      map[a.categoryName] = (map[a.categoryName] ?? 0) + a.balanceCents;
    }
    _filteredByCategory = map.entries
        .map((e) => _CategorySummary(
              name: e.key,
              amount: e.value.abs(),
              color: categoryColorByName(e.key),
            ))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    _filteredRanking = List<AssetAccount>.from(_filteredAccounts)
      ..sort((a, b) => b.balanceCents.abs().compareTo(a.balanceCents.abs()));

    _filteredTotal = _filteredAccounts.fold(0, (s, a) => s + a.balanceCents.abs());
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
        onTap: () {
          if (_selectedType == index) return;
          setState(() {
            _selectedType = index;
            _recompute();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: spacingM),
          color: isSelected ? themeColor : Colors.transparent,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: isSelected ? textFilterActive : textFilterInactive,
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
          padding: const EdgeInsets.symmetric(horizontal: spacingM, vertical: spacingXS),
          decoration: BoxDecoration(
            color: colorDivider,
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          child: Text(
            _yearLabel,
            style: textTagSmall,
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
                showFlatZero: _filteredAccounts.isEmpty,
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
      child: SizedBox(
        height: 220,
        child: _AssetPieChart(key: const ValueKey('pie'), data: data, total: total),
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
//  走势图（syncfusion SfCartesianChart + LineSeries）
// ======================================================================

class _TrendLineChart extends StatelessWidget {
  final List<AssetAccount> accounts;
  final Color themeColor;
  final bool showFlatZero;

  const _TrendLineChart({
    required this.accounts,
    required this.themeColor,
    this.showFlatZero = false,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentMonth = now.month;

    List<_TrendPoint> points;
    if (showFlatZero || accounts.isEmpty) {
      points = List.generate(
        currentMonth,
        (i) => _TrendPoint(month: i + 1, value: 0),
      );
    } else {
      final total = accounts
          .where((a) => !a.isDebtAccount)
          .fold(0, (s, a) => s + a.balanceCents);
      final debt = accounts
          .where((a) => a.isDebtAccount)
          .fold(0, (s, a) => s + a.balanceCents.abs());
      final net = total - debt;

      // TODO: 接入真实历史月度余额快照数据，当前为占位随机值
      final rand = _SimpleRandom(42);
      points = [];
      for (var i = 0; i < currentMonth - 1; i++) {
        final value = net * (0.8 + rand.nextDouble() * 0.4);
        points.add(_TrendPoint(month: i + 1, value: value.toInt()));
      }
      points.add(_TrendPoint(month: currentMonth, value: net));
    }

    final values = points.map((p) => p.value.toDouble()).toList();
    final minY = values.isEmpty
        ? -1.0
        : (values.reduce((a, b) => a < b ? a : b) == 0
            ? -1.0
            : values.reduce((a, b) => a < b ? a : b) * 0.9);
    final maxY = values.isEmpty
        ? 1.0
        : (values.reduce((a, b) => a > b ? a : b) == 0
            ? 1.0
            : values.reduce((a, b) => a > b ? a : b) * 1.1);

    return SfCartesianChart(
      margin: const EdgeInsets.all(0),
      plotAreaBorderWidth: 0,
      primaryXAxis: NumericAxis(
        minimum: 0,
        maximum: (currentMonth - 1).toDouble(),
        interval: 1,
        majorGridLines: const MajorGridLines(width: 0),
        axisLine: const AxisLine(width: 0),
        labelStyle: textChartLabel,
        axisLabelFormatter: (details) {
          final month = (double.tryParse(details.text) ?? 0).toInt() + 1;
          return ChartAxisLabel('$month月', details.textStyle);
        },
      ),
      primaryYAxis: NumericAxis(
        minimum: minY,
        maximum: maxY,
        isVisible: false,
      ),
      tooltipBehavior: TooltipBehavior(
        enable: true,
        duration: 2000,
        animationDuration: 0,
        header: '',
        format: 'point.x月\npoint.y',
        textStyle: textChartTooltip,
        color: colorTextPrimary,
      ),
      series: <LineSeries<_TrendPoint, num>>[
        LineSeries<_TrendPoint, num>(
          dataSource: points,
          xValueMapper: (point, _) => point.month - 1,
          yValueMapper: (point, _) => point.value,
          color: colorTextPrimary,
          width: 1.5,
          markerSettings: MarkerSettings(
            isVisible: true,
            shape: DataMarkerType.circle,
            height: 8,
            width: 8,
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
  final int month;
  final int value;
  const _TrendPoint({required this.month, required this.value});
}

/// 简单伪随机数生成器（不依赖 dart:math）
class _SimpleRandom {
  int _seed;
  _SimpleRandom(this._seed);
  double nextDouble() {
    _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
    return _seed / 0x7fffffff;
  }
}

// ======================================================================
//  饼图（syncfusion DoughnutSeries + 引线）
// ======================================================================

class _AssetPieChart extends StatelessWidget {
  final List<_CategorySummary> data;
  final int total;

  const _AssetPieChart({super.key, required this.data, required this.total});

  @override
  Widget build(BuildContext context) {
    return SfCircularChart(
      margin: EdgeInsets.zero,
      series: <DoughnutSeries<_CategorySummary, String>>[
        DoughnutSeries<_CategorySummary, String>(
          animationDuration: 0,
          dataSource: data,
          xValueMapper: (_CategorySummary item, _) => item.name,
          yValueMapper: (_CategorySummary item, _) => item.amount,
          pointColorMapper: (_CategorySummary item, _) => item.color,
          radius: '70%',
          innerRadius: '50%',
          dataLabelMapper: (_CategorySummary item, _) {
            final pct = total > 0 ? (item.amount / total * 100).toStringAsFixed(1) : '0.0';
            return '${item.name} $pct%';
          },
          dataLabelSettings: const DataLabelSettings(
            isVisible: true,
            labelPosition: ChartDataLabelPosition.outside,
            connectorLineSettings: ConnectorLineSettings(
              type: ConnectorType.line,
              length: '15%',
            ),
          ),
        ),
      ],
      tooltipBehavior: TooltipBehavior(enable: true),
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
                child: Text(account.displayName, style: textBody),
              ),
              Text(
                '$percent%',
                style: textItemSub,
              ),
              const SizedBox(width: spacingS),
              Text(
                formatAmount(account.balanceCents),
                style: textAccountAmount,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(radiusTiny),
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
