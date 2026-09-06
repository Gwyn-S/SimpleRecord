import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';

/// 选项栏单项：图标 + 文字，用于记账页/转账页底部选项。
class OptionBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const OptionBarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSizeMedium, color: colorTextPrimary),
          const SizedBox(width: spacingXS),
          Text(
            label,
            style: textSecondary.copyWith(
              fontSize: 14,
              color: colorTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
