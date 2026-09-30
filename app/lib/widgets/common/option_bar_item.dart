import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';

/// 选项栏单项：图标 + 文字，用于记账页/转账页底部选项。
class OptionBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 为空时按内容自适应；传入则占满该宽度并居中。
  final double? width;

  const OptionBarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.width,
  });

  /// 标签文字样式，测量与渲染共用同一份，保证量出来的宽度就是实际宽度。
  static TextStyle get labelStyle =>
      textSecondary.copyWith(fontSize: 14, color: colorTextPrimary);

  /// 量出某个标签不被压缩时所需的完整宽度（图标 + 间距 + 文字 + 内边距）。
  static double measureWidth(String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width + iconSizeMedium + spacingXS + spacingXS * 2;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: heightOptionBar,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: spacingXS),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: iconSizeMedium, color: colorTextPrimary),
                  const SizedBox(width: spacingXS),
                  Text(label, style: labelStyle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
