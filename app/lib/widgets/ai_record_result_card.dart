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
          _buildRow('类型', result.isExpense ? '支出' : '收入'),
          _buildRow('分类', result.categoryName),
          _buildRow('金额', '${(result.amountCents / 100).toStringAsFixed(2)}元'),
          if (result.remark.isNotEmpty) _buildRow('备注', result.remark),
        ],
      ),
    );
  }

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
