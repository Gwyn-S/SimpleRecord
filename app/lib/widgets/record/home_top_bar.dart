import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';

/// 顶栏可点格的边长下限（实际宽度由屏宽自动平分，此处仅作保护）。
const double _kCellMin = 32;

/// 年月文字样式，测量与渲染必须共用同一个实例，否则宽度算不准。
const TextStyle _kMonthStyle = TextStyle(
  fontSize: 19,
  fontWeight: FontWeight.w800,
  color: colorTextOnPrimary,
);

class HomeTopBar extends StatelessWidget {
  final String monthLabel;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback? onMonthLabelTap;
  final VoidCallback? onLedgerTap;
  final VoidCallback? onBackupTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onUserTap;

  const HomeTopBar({
    super.key,
    required this.monthLabel,
    required this.onPrevMonth,
    required this.onNextMonth,
    this.onMonthLabelTap,
    this.onLedgerTap,
    this.onBackupTap,
    this.onSearchTap,
    this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: heightHeaderBar,
      padding: const EdgeInsets.symmetric(horizontal: spacingS),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avail = constraints.maxWidth;

          // 量出年月文字的真实宽度，其余宽度由 6 个格平分，保证每格完全相等且铺满整行。
          final labelWidth = _measureLabel(monthLabel);
          final cell = math.max(_kCellMin, (avail - labelWidth) / 6);

          return Material(
            color: Colors.transparent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _iconCell(Icons.book_outlined, cell, onLedgerTap),
                _iconCell(Icons.backup_outlined, cell, onBackupTap),
                _iconCell(Icons.keyboard_arrow_left, cell, onPrevMonth),
                _monthLabel(monthLabel, labelWidth, cell),
                _iconCell(Icons.keyboard_arrow_right, cell, onNextMonth),
                _iconCell(Icons.search, cell, onSearchTap),
                _iconCell(Icons.person_outline, cell, onUserTap),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 真实测量年月文字宽度（含左右内边距），避免写死 60 之类的估值。
  double _measureLabel(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _kMonthStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width + spacingXS * 2;
  }

  Widget _iconCell(IconData icon, double size, VoidCallback? onTap) {
    return SizedBox(
      width: size,
      height: size,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radiusSmall),
        child: Center(
          child: Icon(icon, size: iconSizeLarge, color: colorTextOnPrimary),
        ),
      ),
    );
  }

  Widget _monthLabel(String text, double width, double cell) {
    return SizedBox(
      width: width,
      height: cell,
      child: InkWell(
        onTap: onMonthLabelTap,
        borderRadius: BorderRadius.circular(radiusSmall),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text, style: _kMonthStyle),
          ),
        ),
      ),
    );
  }
}
