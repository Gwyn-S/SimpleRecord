String formatAmount(double v) => v.toStringAsFixed(2);

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String formatDate(DateTime d) {
  return '${d.month}月${d.day}日 ${_weekdays[(d.weekday - 1) % 7]}';
}

String formatMonthLabel(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}
