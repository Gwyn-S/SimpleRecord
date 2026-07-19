import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const scaffoldBackground = Color(0xFFF3F3F3);

final themeColorNotifier = ValueNotifier<Color>(const Color(0xFF009688));

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
