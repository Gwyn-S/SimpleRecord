import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';

/// 设置页通用列表项：白底整行可点击，右侧可选 trailing + 右箭头。
class SettingsItem extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback onTap;

  const SettingsItem({
    super.key,
    required this.title,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: spacingL),
        height: heightOptionBar,
        child: Row(
          children: [
            Text(title, style: textListItem),
            const Spacer(),
            trailing ?? const SizedBox.shrink(),
            const SizedBox(width: spacingS),
            Icon(
              Icons.chevron_right,
              size: iconSizeDefault,
              color: colorTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
