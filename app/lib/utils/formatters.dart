import 'calculator.dart';

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

const weekdaysFull = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const weekdaysShort = ['一', '二', '三', '四', '五', '六', '日'];
const _weekdays = weekdaysFull;

String formatDate(DateTime d) {
  return '${d.month}月${d.day}日 ${_weekdays[(d.weekday - 1) % 7]}';
}

/// yyyy-MM-dd
String formatDateYmd(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String formatMonthLabel(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

/// 两位补零。
String pad2(int n) => n.toString().padLeft(2, '0');

/// DateTime → epoch day（用于 SQLite 整型日期存储）。
int toEpochDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1970)).inDays;

/// epoch day → DateTime（toEpochDay 的逆运算）。
DateTime fromEpochDay(int day) => DateTime.utc(1970).add(Duration(days: day));

/// 日期选择器显示："今天" 或 "M月D日"。
String formatSelectedDate(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final selected = DateTime(d.year, d.month, d.day);
  if (selected == today) return '今天';
  return '${d.month}月${d.day}日';
}

/// 文件大小格式化：B / KB / MB。
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// 日期时间格式化：yyyy-MM-dd HH:mm:ss。
String formatDateTime(DateTime d) {
  return '${d.year}-${pad2(d.month)}-${pad2(d.day)} ${pad2(d.hour)}:${pad2(d.minute)}:${pad2(d.second)}';
}

/// 解析金额表达式为分，失败返回 (null, 错误信息)。
(int cents, String? error) parseAmountCents(String expr) {
  final result = evaluate(expr);
  final parsed = double.tryParse(result);
  if (parsed == null) return (0, '金额无效');
  if (parsed < 0) return (0, '金额不能为负');
  final cents = yuanToCents(result);
  if (cents == 0) return (0, '请输入金额');
  return (cents, null);
}
