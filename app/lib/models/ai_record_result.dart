class AiRecordResult {
  final bool isExpense;
  final String categoryName;
  final int amountCents;
  final String remark;
  final DateTime date;

  const AiRecordResult({
    required this.isExpense,
    required this.categoryName,
    required this.amountCents,
    this.remark = '',
    required this.date,
  });
}
