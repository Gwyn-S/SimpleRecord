import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/record.dart';
import '../utils/formatters.dart';

class BillDetailSheet extends StatelessWidget {
  final Record record;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  const BillDetailSheet({
    super.key,
    required this.record,
    required this.onDelete,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(spacingL, spacingM, spacingL, spacingS),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('账单详情', style: textTitleBold),
                const Spacer(),
                if (onEdit != null)
                  TextButton(
                    onPressed: onEdit,
                    child: const Text('修改', style: TextStyle(color: colorTextPrimary)),
                  ),
                TextButton(
                  onPressed: onDelete,
                  child: const Text('删除', style: TextStyle(color: colorDeleteDark)),
                ),
              ],
            ),
            const Divider(height: 1, thickness: borderWidthThin, color: colorDivider),
            const SizedBox(height: spacingM),
            _detailRow('分类', record.categoryName),
            if (record.remark.isNotEmpty) _detailRow('备注', record.remark),
            if (record.tag != null) _detailRow('标签', record.tag!),
            _detailRow('金额', '${record.isExpense ? '-' : '+'}${formatAmount(record.amountCents)}'),
            _detailRow('账户', record.accountName ?? '未选择'),
            _detailRow('日期', formatDate(record.date)),
            _detailRow('录入时间', _formatDateTime(record.createdAt)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: spacingS),
      child: Row(
        children: [
          Text(label, style: textHint),
          const Spacer(),
          Text(value, style: textBody),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
