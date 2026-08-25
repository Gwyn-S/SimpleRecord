import 'dart:math';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class PieSectorData {
  final String name;
  final int amount;
  final Color color;

  const PieSectorData({
    required this.name,
    required this.amount,
    required this.color,
  });
}

class DonutPieChart extends StatefulWidget {
  final List<PieSectorData> data;
  final int total;

  const DonutPieChart({super.key, required this.data, required this.total});

  @override
  State<DonutPieChart> createState() => _DonutPieChartState();
}

class _DonutPieChartState extends State<DonutPieChart> {
  double _rotation = 0;
  double _lastAngle = 0;

  double _getAngle(Offset center, Offset point) {
    return (point - center).direction;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final center = Offset(w / 2, h / 2);
        final radius = h * 0.35;
        return GestureDetector(
          onPanStart: (details) {
            _lastAngle = _getAngle(center, details.localPosition);
          },
          onPanUpdate: (details) {
            final currentAngle = _getAngle(center, details.localPosition);
            final delta = currentAngle - _lastAngle;
            setState(() {
              _rotation += delta;
            });
            _lastAngle = currentAngle;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: Transform.rotate(
                  angle: _rotation,
                  child: SfCircularChart(
                    margin: EdgeInsets.zero,
                    series: <DoughnutSeries<PieSectorData, String>>[
                      DoughnutSeries<PieSectorData, String>(
                        animationDuration: 0,
                        dataSource: widget.data,
                        xValueMapper: (PieSectorData item, _) => item.name,
                        yValueMapper: (PieSectorData item, _) => item.amount,
                        pointColorMapper: (PieSectorData item, _) => item.color,
                        radius: '70%',
                        innerRadius: '50%',
                        dataLabelSettings: const DataLabelSettings(isVisible: false),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _PieLeaderPainter(
                    data: widget.data,
                    total: widget.total,
                    center: center,
                    radius: radius,
                    rotation: _rotation,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PieLeaderPainter extends CustomPainter {
  final List<PieSectorData> data;
  final int total;
  final Offset center;
  final double radius;
  final double rotation;

  _PieLeaderPainter({
    required this.data,
    required this.total,
    required this.center,
    required this.radius,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || total == 0) return;

    final linePaint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final extendLength = radius * 0.1;
    double startAngle = -pi / 2 + rotation;

    for (final item in data) {
      final sweepAngle = (item.amount / total) * 2 * pi;
      final midAngle = startAngle + sweepAngle / 2;

      final startX = center.dx + radius * cos(midAngle);
      final startY = center.dy + radius * sin(midAngle);
      final breakX = center.dx + (radius + extendLength) * cos(midAngle);
      final breakY = center.dy + (radius + extendLength) * sin(midAngle);
      final isRight = breakX > center.dx;
      final endX = isRight ? breakX + 18 : breakX - 18;

      linePaint.color = item.color;
      canvas.drawLine(Offset(startX, startY), Offset(breakX, breakY), linePaint);
      canvas.drawLine(Offset(breakX, breakY), Offset(endX, breakY), linePaint);

      final pct = (item.amount / total * 100).toStringAsFixed(1);
      final textPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(text: item.name, style: TextStyle(fontSize: 10, color: item.color)),
            TextSpan(text: ' $pct%', style: TextStyle(fontSize: 10, color: item.color)),
          ],
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(isRight ? endX + 4 : endX - textPainter.width - 4, breakY - textPainter.height / 2));

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(_PieLeaderPainter old) =>
      total != old.total || rotation != old.rotation;
}
