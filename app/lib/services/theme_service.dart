import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_colors.dart';

final themeColorNotifier = ValueNotifier<Color>(const Color(0xFF009688));

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color primary;

  const AppThemeColors({required this.primary});

  @override
  AppThemeColors copyWith({Color? primary}) =>
      AppThemeColors(primary: primary ?? this.primary);

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      primary: Color.lerp(primary, other.primary, t)!,
    );
  }
}

ThemeData buildAppTheme(Color primary) {
  return ThemeData(
    brightness: Brightness.light,
    fontFamily:
        defaultTargetPlatform == TargetPlatform.android ? 'sans-serif' : null,
    scaffoldBackgroundColor: colorBackgroundCard,
    colorScheme: ColorScheme.fromSeed(seedColor: primary),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    extensions: [AppThemeColors(primary: primary)],
  );
}

Future<void> loadThemeColor() async {
  final prefs = await SharedPreferences.getInstance();
  final colorValue = prefs.getInt('themeColor');
  if (colorValue != null) {
    themeColorNotifier.value = Color(colorValue);
  }
}

Future<void> saveThemeColor(Color color) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('themeColor', color.toARGB32());
}
