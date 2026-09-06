import 'package:flutter/material.dart';

import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';

/// 阻塞式进度 Dialog：显示 Loader + 文案，期间不可关闭。
Dialog busyDialog(String text) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(spacingXXL),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: spacingL),
            Text(text, style: textBody),
          ],
        ),
      ),
    );