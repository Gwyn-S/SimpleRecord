import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import 'settings.dart';

/// 当前主题色；变更后各页面据此重建主题。
final themeColorNotifier = ValueNotifier<Color>(colorPrimaryDefault);

/// 自定义 ThemeExtension 扩展色（当前仅主色）。
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color primary;

  const AppThemeColors({required this.primary});

  @override
  AppThemeColors copyWith({Color? primary}) =>
      AppThemeColors(primary: primary ?? this.primary);

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(primary: Color.lerp(primary, other.primary, t)!);
  }
}

/// 依据主色构建全局亮色主题。
ThemeData buildAppTheme(Color primary) {
  return ThemeData(
    brightness: Brightness.light,
    fontFamily: defaultTargetPlatform == TargetPlatform.android
        ? 'sans-serif'
        : null,
    scaffoldBackgroundColor: colorBackgroundCard,
    colorScheme: ColorScheme.fromSeed(seedColor: primary),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
    ),
    extensions: [AppThemeColors(primary: primary)],
  );
}

Future<void> loadThemeColor() async {
  final colorValue = await Settings.getInt('themeColor');
  if (colorValue != null) {
    themeColorNotifier.value = Color(colorValue);
  }
}

Future<void> saveThemeColor(Color color) async {
  await Settings.setInt('themeColor', color.toARGB32());
}
