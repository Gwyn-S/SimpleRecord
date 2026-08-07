/// 金额单位是分（int），格式化时转回元显示。
String formatAmount(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// 解析元（字符串，可能带小数）为分。
int yuanToCents(String s) {
  final parts = s.split('.');
  final yuan = int.parse(parts[0] == '' ? '0' : parts[0]);
  final frac = (parts.length > 1 ? parts[1] : '').padRight(2, '0').substring(0, 2);
  return yuan * 100 + int.parse(frac);
}

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String formatDate(DateTime d) {
  return '${d.month}月${d.day}日 ${_weekdays[(d.weekday - 1) % 7]}';
}

String formatMonthLabel(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}
