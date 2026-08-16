import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../models/category.dart';
import '../models/record.dart';
import '../services/record_service.dart';
import '../utils/formatters.dart';
import 'bill_detail_sheet.dart';

class RecordItem extends StatelessWidget {
  final Record record;
  final VoidCallback? onEdit;
  final bool showDate;

  const RecordItem({
    super.key,
    required this.record,
    this.onEdit,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.help_outline;
    final categories = record.isExpense ? expenseCategories : incomeCategories;
    for (final c in categories) {
      if (c.name == record.categoryName) {
        icon = c.icon;
        break;
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showActions(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingM),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: colorIconLightBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: iconSizeDefault, color: colorIconGray),
            ),
            const SizedBox(width: spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.categoryName,
                    style: textListItem,
                  ),
                  if (record.tag != null || record.remark.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (record.tag != null) ...[
                          Text(
                            record.tag!,
                            // 统一行高，避免中英文混排时与备注高度不一致
                            style: textItemSub.copyWith(height: 1.4),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: spacingXS),
                        ],
                        if (record.remark.isNotEmpty)
                          Expanded(
                            child: Text(
                              record.remark,
                              style: textItemSub.copyWith(height: 1.4),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  if (showDate)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        formatDateYmd(record.date),
                        style: textItemSub,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${record.isExpense ? '-' : '+'}${formatAmount(record.amountCents)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: record.isExpense
                        ? colorExpense
                        : Theme.of(context).extension<AppThemeColors>()!.primary,
                  ),
                ),
                if (record.accountName != null)
                  Text(
                    record.accountName!,
                    style: textItemSub,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colorBackgroundCard,
      builder: (sheetContext) => BillDetailSheet(
        record: record,
        onEdit: () {
          Navigator.pop(sheetContext);
          onEdit?.call();
        },
        onDelete: () async {
          Navigator.pop(sheetContext);
          await deleteRecord(record.id);
        },
      ),
    );
  }
}
