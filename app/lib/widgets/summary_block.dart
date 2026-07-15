import 'package:flutter/material.dart';

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
    const white = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white);
    if (large) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: white),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text('¥', style: white),
                const SizedBox(width: 4),
                Text(amount ?? '0.00', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w400, letterSpacing: -1, color: Colors.white)),
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
            Text(label, style: white),
            const SizedBox(width: 4),
            Text(emptyText!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
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
          Text(label, style: white),
          const SizedBox(width: 4),
          const Text('¥', style: white),
          const SizedBox(width: 2),
          Text(amount ?? '0.00', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400, letterSpacing: -1, color: Colors.white)),
        ],
      ),
    );
  }
}
