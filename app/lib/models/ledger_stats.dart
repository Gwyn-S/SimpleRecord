/// 单个账本的记录数与收支合计（金额单位：分）。
class LedgerStats {
  const LedgerStats({
    required this.count,
    required this.income,
    required this.expense,
  });
  final int count;
  final int income;
  final int expense;
}
