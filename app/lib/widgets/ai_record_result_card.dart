import 'package:flutter/material.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/ai_record_result.dart';
import '../models/asset_account.dart';
import '../utils/formatters.dart';

class AiRecordResultCard extends StatelessWidget {
  final AiRecordResult result;
  final List<AssetAccount> accounts;

  const AiRecordResultCard({super.key, required this.result, this.accounts = const []});

  @override
  Widget build(BuildContext context) {
    final accountNames = {for (final a in accounts) a.id: a.displayName};
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
          if (result.accountId.isNotEmpty) _buildRow('账户', _accountDisplay(result.accountId, accountNames)),
          if (result.fromAccountId.isNotEmpty) _buildRow('转出账户', _accountDisplay(result.fromAccountId, accountNames)),
          if (result.toAccountId.isNotEmpty) _buildRow('转入账户', _accountDisplay(result.toAccountId, accountNames)),
          if (result.remark.isNotEmpty) _buildRow('备注', result.remark),
          _buildRow('日期', '${result.date.year}-${pad2(result.date.month)}-${pad2(result.date.day)}'),
        ],
      ),
    );
  }

  String _accountDisplay(String id, Map<String, String> accountNames) {
    return accountNames[id] ?? id;
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

/// AI 记账结果区（结果列表 + 确认按钮），文字/图片/语音三页共用。
/// 需置于支持 Flex（Column/Row 的 Expanded）的父级中提供高度约束。
class AiRecordResultSection extends StatelessWidget {
  const AiRecordResultSection({
    super.key,
    required this.results,
    required this.accounts,
    required this.onSave,
  });

  final List<AiRecordResult> results;
  final List<AssetAccount> accounts;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: spacingL),
        Expanded(
          child: ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => const SizedBox(height: spacingM),
            itemBuilder: (_, i) =>
                AiRecordResultCard(result: results[i], accounts: accounts),
          ),
        ),
        const SizedBox(height: spacingM),
        SizedBox(
          height: 44,
          child: FilledButton(
            onPressed: onSave,
            child: Text(
              '确认记账${results.length > 1 ? '(${results.length}笔)' : ''}',
            ),
          ),
        ),
      ],
    );
  }
}