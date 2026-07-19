import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../theme.dart';
import '../icon/app_icons.dart';
import '../models/record.dart';

class RecordItem extends StatelessWidget {
  final Record record;
  final String Function(double) fmt;

  const RecordItem({
    super.key,
    required this.record,
    this.fmt = _defaultFmt,
  });

  static String _defaultFmt(double v) => v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.help_outline;
    for (final c in [...expenseCategories, ...incomeCategories]) {
      if (c.name == record.categoryName) {
        icon = c.icon;
        break;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingM),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: colorBackgroundLight,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: iconSizeDefault, color: colorTextPrimary),
          ),
          const SizedBox(width: spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.categoryName,
                  style: const TextStyle(fontSize: 15, color: colorTextPrimary),
                ),
                if (record.remark.isNotEmpty)
                  Text(
                    record.remark,
                    style: const TextStyle(fontSize: 12, color: colorTextSecondary),
                  ),
              ],
            ),
          ),
          ValueListenableBuilder<Color>(
            valueListenable: themeColorNotifier,
            builder: (context, color, _) => Text(
              '${record.isExpense ? '-' : '+'}${fmt(record.amount)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: record.isExpense ? colorExpense : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
