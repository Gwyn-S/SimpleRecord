import 'package:flutter/material.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFF5F5F5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF333333)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.categoryName,
                  style: const TextStyle(fontSize: 15, color: Colors.black),
                ),
                if (record.remark.isNotEmpty)
                  Text(
                    record.remark,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
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
                color: record.isExpense ? const Color(0xFFC62828) : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
