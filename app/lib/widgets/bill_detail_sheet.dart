import 'dart:io';

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/record.dart';
import '../utils/formatters.dart';
import 'full_image_viewer.dart';

class BillDetailSheet extends StatelessWidget {
  final Record record;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String>? onDeleteImage;

  const BillDetailSheet({
    super.key,
    required this.record,
    required this.onDelete,
    this.onEdit,
    this.onDeleteImage,
  });

  @override
  Widget build(BuildContext context) {
    final imagePaths = record.imagePaths;
    final padH = const EdgeInsets.symmetric(horizontal: spacingL);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(spacingL, spacingM, spacingL, spacingM),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('账单详情', style: textTitleBold),
              const Spacer(),
              if (onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  child: const Text('修改', style: textButtonDefault),
                ),
              if (onEdit != null) const SizedBox(width: spacingXS),
              GestureDetector(
                onTap: onDelete,
                child: const Text('删除', style: textButtonDanger),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: borderWidthThin, color: colorDivider),
        Padding(padding: padH, child: _detailRow('分类', record.categoryName)),
        _buildDivider(),
        if (record.remark.isNotEmpty) ...[
          Padding(padding: padH, child: _detailRow('备注', record.remark)),
          _buildDivider(),
        ],
        if (record.tag != null) ...[
          Padding(padding: padH, child: _detailRow('标签', record.tag!)),
          _buildDivider(),
        ],
        Padding(padding: padH, child: _detailRow('金额', '${record.isExpense ? '-' : '+'}${formatAmount(record.amountCents)}')),
        _buildDivider(),
        Padding(padding: padH, child: _detailRow('账户', record.accountName ?? '未选择')),
        _buildDivider(),
        Padding(padding: padH, child: _detailRow('日期', formatDate(record.date))),
        _buildDivider(),
        Padding(padding: padH, child: _detailRow('录入时间', formatDateTime(record.createdAt))),
        if (imagePaths != null && imagePaths.isNotEmpty) ...[
          _buildDivider(),
          Padding(
            padding: padH,
            child: SizedBox(
              height: heightOptionBar,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: spacingS),
                itemCount: imagePaths.length,
                separatorBuilder: (_, index) => const SizedBox(width: spacingS),
                itemBuilder: (context, index) {
                  final file = File(imagePaths[index]);
                  return GestureDetector(
                    onTap: () => _showFullImage(context, imagePaths, index),
                    child: Image.file(
                      file,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showFullImage(BuildContext context, List<String> paths, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullImageViewer(
          imagePaths: paths,
          initialIndex: initialIndex,
          onDelete: (i) {
            if (paths.isNotEmpty && i >= 0 && i < paths.length) {
              onDeleteImage?.call(paths[i]);
            }
          },
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return SizedBox(
      height: heightOptionBar,
      child: Row(
        children: [
          Text(label, style: textHint),
          const Spacer(),
          Text(value, style: textBody),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: borderWidthThin, color: colorDivider);
  }
}
