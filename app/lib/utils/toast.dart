import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';

void showToast(BuildContext context, String text,
    {Duration duration = const Duration(seconds: 2)}) {
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(builder: (_) => _Toast(text: text));
  overlay.insert(entry);
  Future.delayed(duration, () => entry.remove());
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
            child: Text(text, style: const TextStyle(color: colorTextPrimary, fontSize: 13)),
          ),
        ),
      ),
    );
  }
}
