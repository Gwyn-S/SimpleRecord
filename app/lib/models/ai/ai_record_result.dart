class AiRecordResult {
  final String type; // expense / income / transfer
  final int amountCents;
  final String categoryName;
  final String accountId;
  final String fromAccountId;
  final String toAccountId;
  final String remark;
  final DateTime date;

  const AiRecordResult({
    required this.type,
    required this.amountCents,
    required this.categoryName,
    this.accountId = '',
    this.fromAccountId = '',
    this.toAccountId = '',
    this.remark = '',
    required this.date,
  });

  bool get isExpense => type == 'expense';
  bool get isIncome => type == 'income';
  bool get isTransfer => type == 'transfer';
}
