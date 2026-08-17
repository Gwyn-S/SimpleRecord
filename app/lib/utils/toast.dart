import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';

void showToast(BuildContext context, String text,
    {Duration duration = const Duration(seconds: 2)}) {
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(builder: (_) => _Toast(text: text));
  overlay.insert(entry);
  Future.delayed(duration, () => entry.remove());
}

/// mounted 安全的 showToast 包装。
void safeShowToast(BuildContext context, String text) {
  if (!context.mounted) return;
  showToast(context, text);
}

class _Toast extends StatelessWidget {
  final String text;
  const _Toast({required this.text});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: spacingXXL, vertical: 10),
            decoration: BoxDecoration(
              color: colorBackgroundToast,
              borderRadius: BorderRadius.circular(radiusLarge),
            ),
            child: Text(text, style: textToast),
          ),
        ),
      ),
    );
  }
}
