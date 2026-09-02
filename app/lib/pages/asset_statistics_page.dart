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
import '../widgets/card_container.dart';
import '../widgets/donut_pie_chart.dart';
import '../widgets/month_year_picker.dart';
import '../widgets/tab_bar.dart';

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
        break;
      case 1:
        _filteredAccounts = _accounts.where((a) => a.isDebtAccount).toList();
        break;
      default:
        _filteredAccounts = _accounts;
        break;
    }

    _filteredByCategory =
        _filteredAccounts
            .where((a) => a.balanceCents != 0)
            .map(
              (a) => _CategorySummary(
                name: a.displayName,
                amount: a.balanceCents.abs(),
                color: categoryColorByName(a.categoryName),
              ),
            )
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    _filteredRanking = List<AssetAccount>.from(_filteredAccounts)
      ..sort((a, b) => b.balanceCents.abs().compareTo(a.balanceCents.abs()));

    _filteredTotal = _filteredAccounts.fold(
      0,
      (s, a) => s + a.balanceCents.abs(),
    );
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
      body: ListView(
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
    return Container(
      decoration: BoxDecoration(
        color: colorBackgroundCard,
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      clipBehavior: Clip.antiAlias,
      child: FilterTabBar(
        tabs: const ['资产', '负债', '净资产'],
        selectedIndex: _selectedType,
        onChanged: (i) {
          setState(() {
            _selectedType = i;
            _recompute();
          });
        },
      ),
    );
  }

  // ======================== 走势图卡片 ========================

  String get _yearLabel => yearLabel(_selectedYear);

  Widget _buildTrendCard(Color themeColor) {
    return CardContainer(
      title: '资产走势图',
      trailing: GestureDetector(
        onTap: _showYearPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: spacingM,
            vertical: spacingXS,
          ),
          decoration: BoxDecoration(
            color: colorDivider,
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          child: Text(_yearLabel, style: textTagSmall),
        ),
      ),
      child: SizedBox(
        height: 180,
        child: _TrendLineChart(
          accounts: _filteredAccounts,
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
      return CardContainer(title: title, child: const SizedBox.shrink());
    }
    return CardContainer(
      title: title,
      child: SizedBox(
        height: 220,
        child: DonutPieChart(
          key: const ValueKey('pie'),
          data: data
              .map(
                (s) => PieSectorData(
                  name: s.name,
                  amount: s.amount,
                  color: s.color,
                ),
              )
              .toList(),
          total: total,
        ),
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
      return CardContainer(title: title, child: const SizedBox.shrink());
    }
    final totalAmount = _filteredTotal;
    return CardContainer(
      title: title,
      child: Column(
        children: ranking.asMap().entries.map((entry) {
          final account = entry.value;
          final ratio = totalAmount > 0
              ? account.balanceCents.abs() / totalAmount
              : 0.0;
          return _RankingRow(account: account, ratio: ratio);
        }).toList(),
      ),
    );
  }
}

// ======================================================================
//  走势图（syncfusion SfCartesianChart + LineSeries + 点击节点显示信息）
// ======================================================================

class _TrendLineChart extends StatelessWidget {
  final List<AssetAccount> accounts;
  final bool showFlatZero;

  const _TrendLineChart({required this.accounts, this.showFlatZero = false});

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
      final rand = SimpleRandom(42);
      points = [];
      for (var i = 0; i < currentMonth - 1; i++) {
        final value = net * (0.8 + rand.nextDouble() * 0.4);
        points.add(_TrendPoint(month: i + 1, value: value.toInt()));
      }
      points.add(_TrendPoint(month: currentMonth, value: net));
    }

    final values = points.map((p) => p.value.toDouble()).toList();
    final (minY, maxY) = computeYRange(values);

    final tooltip = TooltipBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      tooltipPosition: TooltipPosition.pointer,
      animationDuration: 0,
      builder:
          (
            dynamic data,
            dynamic point,
            dynamic series,
            int pointIndex,
            int seriesIndex,
          ) {
            final p = points[pointIndex];
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: spacingS,
                vertical: spacingXS,
              ),
              decoration: BoxDecoration(
                color: colorTextPrimary,
                borderRadius: BorderRadius.circular(radiusTiny),
              ),
              child: Text(
                '${p.month}月 ${formatAmount(p.value)}',
                style: textChartTooltip,
              ),
            );
          },
    );

    return SfCartesianChart(
      margin: const EdgeInsets.all(0),
      plotAreaBorderWidth: 0,
      primaryXAxis: NumericAxis(
        minimum: 0,
        maximum: (currentMonth - 1).toDouble(),
        interval: 1,
        majorGridLines: const MajorGridLines(width: 0),
        majorTickLines: const MajorTickLines(size: 0),
        axisLine: const AxisLine(width: 0),
        labelStyle: textChartLabel,
        axisLabelFormatter: (details) {
          final month = (double.tryParse(details.text) ?? 0).toInt() + 1;
          return ChartAxisLabel('$month月', details.textStyle);
        },
      ),
      primaryYAxis: NumericAxis(minimum: minY, maximum: maxY, isVisible: false),
      tooltipBehavior: tooltip,
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
            height: 5,
            width: 5,
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

// ======================================================================
//  排行榜行
// ======================================================================

class _RankingRow extends StatelessWidget {
  final AssetAccount account;
  final double ratio;

  const _RankingRow({required this.account, required this.ratio});

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
              AccountAvatar(
                account: account,
                size: iconSizeSmall,
                color: themeColor,
              ),
              const SizedBox(width: spacingS),
              Expanded(child: Text(account.displayName, style: textBody)),
              Text('$percent%', style: textItemSub),
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
