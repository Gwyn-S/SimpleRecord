import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';

class SummaryBlock extends StatelessWidget {
  final String label;
  final String? amount;
  final bool large;
  final String? emptyText;

  const SummaryBlock(
    this.label,
    this.amount, {
    super.key,
    this.large = false,
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    if (large) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: textSecondary.copyWith(color: colorTextOnPrimary)),
            const SizedBox(height: spacingXS),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('¥', style: textSecondary.copyWith(color: colorTextOnPrimary)),
                const SizedBox(width: spacingXS),
                Text(amount ?? '0.00', style: textAmountLarge),
              ],
            ),
          ],
        ),
      );
    }
    if (emptyText != null && amount == null) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(label, style: textSecondary.copyWith(color: colorTextOnPrimary)),
            const SizedBox(width: spacingXS),
            Text(emptyText!, style: textSummaryEmpty),
          ],
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label, style: textSecondary.copyWith(color: colorTextOnPrimary)),
          const SizedBox(width: spacingXS),
          Text('¥', style: textSecondary.copyWith(color: colorTextOnPrimary)),
          const SizedBox(width: spacingXXS),
          Text(amount ?? '0.00', style: textAmountMedium),
        ],
      ),
    );
  }
}
