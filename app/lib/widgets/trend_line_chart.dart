import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../utils/formatters.dart';

/// 折线图数据点
class TrendPoint {
  final String label;
  final int value;

  const TrendPoint({required this.label, required this.value});
}

/// 公共折线图组件
class TrendLineChart extends StatelessWidget {
  final List<TrendPoint> points;
  final bool showMarkers;
  final bool showTooltipHeader;
  final double? height;
  final String Function(TrendPoint)? tooltipFormatter;

  const TrendLineChart({
    super.key,
    required this.points,
    this.showMarkers = true,
    this.showTooltipHeader = true,
    this.height,
    this.tooltipFormatter,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(height: height ?? 160);
    }

    final values = points.map((p) => p.value.toDouble()).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);

    final tooltip = TooltipBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      tooltipPosition: TooltipPosition.pointer,
      animationDuration: 0,
      header: showTooltipHeader ? '' : null,
      canShowMarker: false,
      builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
        final p = points[pointIndex];
        final text = tooltipFormatter != null
            ? tooltipFormatter!(p)
            : '${p.label} ${formatAmount(p.value)}';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        );
      },
    );

    final interval = points.length > 31 ? (points.length / 10).ceil() : 1;

    return SizedBox(
      height: height ?? 160,
      child: SfCartesianChart(
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
        series: <LineSeries<TrendPoint, String>>[
          LineSeries<TrendPoint, String>(
            dataSource: points,
            xValueMapper: (point, _) => point.label,
            yValueMapper: (point, _) => point.value,
            color: colorTextPrimary,
            width: 1.5,
            markerSettings: MarkerSettings(
              isVisible: showMarkers,
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
      ),
    );
  }
}
