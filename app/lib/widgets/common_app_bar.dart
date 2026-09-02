import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/theme_service.dart';

class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const CommonAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.bottom,
  }) : assert(title != null || titleWidget != null);

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return AppBar(
      title: titleWidget ?? Text(title!),
      backgroundColor: themeColor,
      foregroundColor: colorTextOnPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '',
        onPressed: () => Navigator.pop(context),
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}
