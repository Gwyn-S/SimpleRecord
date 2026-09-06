import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';

class SummaryBlock extends StatelessWidget {
  final String label;
  final String? amount;
  final bool large;
  final String? emptyText;
  final VoidCallback? onTap;

  const SummaryBlock(
    this.label,
    this.amount, {
    super.key,
    this.large = false,
    this.emptyText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (large) {
      content = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: textSecondary.copyWith(color: colorTextOnPrimary),
            ),
            const SizedBox(height: spacingXS),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '¥',
                  style: textSecondary.copyWith(color: colorTextOnPrimary),
                ),
                const SizedBox(width: spacingXS),
                Text(amount ?? '0.00', style: textAmountStat),
              ],
            ),
          ],
        ),
      );
    } else if (emptyText != null && amount == null) {
      content = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: textSecondary.copyWith(color: colorTextOnPrimary),
            ),
            const SizedBox(width: spacingXS),
            Text(emptyText!, style: textSummaryEmpty),
          ],
        ),
      );
    } else {
      content = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: textSecondary.copyWith(color: colorTextOnPrimary),
            ),
            const SizedBox(width: spacingXS),
            Text('¥', style: textSecondary.copyWith(color: colorTextOnPrimary)),
            const SizedBox(width: spacingXXS),
            Text(amount ?? '0.00', style: textAmountStat),
          ],
        ),
      );
    }
    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}
