import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../theme.dart';
import '../models/category.dart';
import '../models/record.dart';
import '../pages/manual_entry_page.dart';
import '../services/record_service.dart';
import '../utils/formatters.dart';
import '../utils/toast.dart';

class RecordItem extends StatelessWidget {
  final Record record;
  final String Function(int) fmt;

  const RecordItem({
    super.key,
    required this.record,
    this.fmt = _defaultFmt,
  });

  static String _defaultFmt(int cents) => formatAmount(cents);

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.help_outline;
    for (final c in [...expenseCategories, ...incomeCategories]) {
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
                '${record.isExpense ? '-' : '+'}${fmt(record.amountCents)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: record.isExpense ? colorExpense : color,
                ),
              ),
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
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(spacingL, spacingM, spacingL, spacingS),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '账单详情',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colorTextPrimary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ManualEntryPage(initialRecord: record),
                        ),
                      );
                    },
                    child: const Text('修改', style: TextStyle(color: colorTextPrimary)),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _confirmDelete(context);
                    },
                    child: const Text('删除', style: TextStyle(color: Color(0xFFC62828))),
                  ),
                ],
              ),
              const Divider(height: 1, thickness: borderWidthThin, color: colorDivider),
              const SizedBox(height: spacingM),
              _detailRow('分类', record.categoryName),
              if (record.remark.isNotEmpty) _detailRow('备注', record.remark),
              _detailRow('金额', '${record.isExpense ? '-' : '+'}${fmt(record.amountCents)}'),
              _detailRow('账户', '未选择'),
              _detailRow('日期', formatDate(record.date)),
              _detailRow('录入时间', _formatDateTime(record.createdAt)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: spacingS),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: colorTextSecondary)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 14, color: colorTextPrimary)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定删除「${record.categoryName} ${formatAmount(record.amountCents)}」这笔记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除', style: TextStyle(color: colorDelete)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await deleteRecord(record.id);
    if (context.mounted) showToast(context, '已删除');
  }
}
