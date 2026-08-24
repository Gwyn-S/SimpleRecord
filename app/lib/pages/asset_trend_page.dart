import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../models/asset_account.dart';
import '../services/theme_service.dart';
import '../utils/formatters.dart';
import '../widgets/card_container.dart';
import '../widgets/month_year_picker.dart';

class AssetTrendPage extends StatefulWidget {
  final AssetAccount account;

  const AssetTrendPage({super.key, required this.account});

  @override
  State<AssetTrendPage> createState() => _AssetTrendPageState();
}

class _AssetTrendPageState extends State<AssetTrendPage> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final dailyPoints = _generateDailyPoints();
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.account.name} 趋势'),
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
          _buildMonthPicker(),
          const SizedBox(height: spacingM),
          _buildTrendCard(dailyPoints),
          const SizedBox(height: spacingM),
          _buildDetailCard(dailyPoints),
        ],
      ),
    );
  }

  Widget _buildMonthPicker() {
    return GestureDetector(
      onTap: _pickMonth,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: spacingM, vertical: spacingXS),
          decoration: BoxDecoration(
            color: colorDivider,
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          child: Text(
            formatMonthLabel(_selectedMonth),
            style: textTagSmall,
          ),
        ),
      ),
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showMonthYearPicker(
      context,
      _selectedMonth,
    );
    if (picked != null && mounted) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month));
    }
  }

  Widget _buildTrendCard(List<_DailyPoint> points) {
    return CardContainer(
      title: '余额走势图',
      child: SizedBox(
        height: 160,
        child: _DailyTrendChart(points: points),
      ),
    );
  }

  Widget _buildDetailCard(List<_DailyPoint> points) {
    return CardContainer(
      title: '余额详情',
      child: SizedBox(
        height: 300,
        child: ListView.separated(
          itemCount: points.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: colorDivider),
          itemBuilder: (context, index) {
            final p = points[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: spacingM, vertical: spacingS),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(p.dateStr, style: textBody),
                  Text(formatAmount(p.value), style: textBody),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<_DailyPoint> _generateDailyPoints() {
    final year = _selectedMonth.year;
    final month = _selectedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final balance = widget.account.balanceCents;

    // TODO: 接入真实每日余额快照数据，当前为占位随机值
    final rand = SimpleRandom(widget.account.id.hashCode & 0x7fffffff);
    final points = <_DailyPoint>[];
    for (var i = daysInMonth; i >= 1; i--) {
      final value = (i == daysInMonth)
          ? balance
          : (balance * (0.8 + rand.nextDouble() * 0.4)).toInt();
      final date = DateTime(year, month, i);
      points.add(_DailyPoint(date: date, value: value));
    }
    return points;
  }
}

// ======================================================================
//  折线图
// ======================================================================

class _DailyTrendChart extends StatelessWidget {
  final List<_DailyPoint> points;

  const _DailyTrendChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final values = points.map((p) => p.value.toDouble()).toList();
    final (minY, maxY) = computeYRange(values);

    final tooltip = TooltipBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      tooltipPosition: TooltipPosition.pointer,
      animationDuration: 0,
      builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
        final p = points[pointIndex];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: spacingS, vertical: spacingXS),
          decoration: BoxDecoration(
            color: colorTextPrimary,
            borderRadius: BorderRadius.circular(radiusTiny),
          ),
          child: Text(
            '${p.date.month}/${p.date.day} ${formatAmount(p.value)}',
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
        maximum: (points.length - 1).toDouble(),
        interval: points.length > 10 ? (points.length / 5).ceilToDouble() : 1,
        majorGridLines: const MajorGridLines(width: 0),
        majorTickLines: const MajorTickLines(size: 0),
        axisLine: const AxisLine(width: 0),
        labelStyle: textChartLabel,
        axisLabelFormatter: (details) {
          final idx = (double.tryParse(details.text) ?? 0).toInt();
          if (idx < 0 || idx >= points.length) return ChartAxisLabel('', details.textStyle);
          final d = points[idx].date;
          return ChartAxisLabel('${d.month}/${d.day}', details.textStyle);
        },
      ),
      primaryYAxis: NumericAxis(
        minimum: minY,
        maximum: maxY,
        isVisible: false,
      ),
      tooltipBehavior: tooltip,
      series: <LineSeries<_DailyPoint, num>>[
        LineSeries<_DailyPoint, num>(
          dataSource: points,
          xValueMapper: (_, index) => index,
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

// ======================================================================
//  数据模型
// ======================================================================

class _DailyPoint {
  final DateTime date;
  final int value;
  const _DailyPoint({required this.date, required this.value});
  String get dateStr => formatDateYmd(date);
}
