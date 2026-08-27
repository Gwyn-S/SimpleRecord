import 'package:flutter/material.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/ai_record_result.dart';

class AiRecordResultCard extends StatelessWidget {
  final AiRecordResult result;

  const AiRecordResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(spacingL),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRow('类型', _typeLabel),
          _buildRow('分类', result.categoryName),
          _buildRow('金额', '${(result.amountCents / 100).toStringAsFixed(2)}元'),
          if (result.accountId.isNotEmpty) _buildRow('账户', result.accountId),
          if (result.fromAccountId.isNotEmpty) _buildRow('转出账户', result.fromAccountId),
          if (result.toAccountId.isNotEmpty) _buildRow('转入账户', result.toAccountId),
          if (result.remark.isNotEmpty) _buildRow('备注', result.remark),
          _buildRow('日期', '${result.date.year}-${_pad(result.date.month)}-${_pad(result.date.day)}'),
        ],
      ),
    );
  }

  String get _typeLabel {
    switch (result.type) {
      case 'expense':
        return '支出';
      case 'income':
        return '收入';
      case 'transfer':
        return '转账';
      default:
        return '支出';
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: spacingS),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: textItemSub),
          ),
          Expanded(
            child: Text(value, style: textListItem),
          ),
        ],
      ),
    );
  }
}