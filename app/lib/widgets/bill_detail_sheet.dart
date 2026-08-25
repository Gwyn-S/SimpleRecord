import 'dart:io';

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
    final imagePaths = record.imagePaths;
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
                    child: const Text('修改', style: textButtonDefault),
                  ),
                TextButton(
                  onPressed: onDelete,
                  child: const Text('删除', style: textButtonDanger),
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
            _detailRow('录入时间', formatDateTime(record.createdAt)),
            if (imagePaths != null && imagePaths.isNotEmpty) ...[
              const SizedBox(height: spacingM),
              Row(
                children: [
                  Text('图片', style: textHint),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: spacingS),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
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
            ],
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, List<String> paths, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullImageViewer(
          imagePaths: paths,
          initialIndex: initialIndex,
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
}

class _FullImageViewer extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;

  const _FullImageViewer({
    required this.imagePaths,
    required this.initialIndex,
  });

  @override
  State<_FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<_FullImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.imagePaths.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) => Center(
                child: Image.file(
                  File(widget.imagePaths[index]),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (widget.imagePaths.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '${_currentIndex + 1} / ${widget.imagePaths.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
