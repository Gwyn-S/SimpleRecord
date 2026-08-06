import '../models/record.dart';
import '../services/record_service.dart';

DateTime weekStart(DateTime day) {
  return day.subtract(Duration(days: day.weekday - 1));
}

final DateTime _epochMonday = DateTime(2020, 1, 6);

int weekPageFromDay(DateTime day) {
  final start = weekStart(day);
  return start.difference(_epochMonday).inDays ~/ 7;
}

DateTime dayFromWeekPage(int page) {
  return _epochMonday.add(Duration(days: page * 7));
}

DateTime monthFromPage(int page) {
  final year = (page + 1) ~/ 12;
  final month = (page + 1) % 12;
  return DateTime(year, month == 0 ? 12 : month);
}

int pageFromMonth(DateTime m) => m.year * 12 + m.month - 1;

List<Record> monthRecords(DateTime month) {
  return allRecords.value.where((r) =>
      r.date.year == month.year &&
      r.date.month == month.month &&
      r.bookId == currentBookId.value).toList();
}

double monthExpense(List<Record> records) => records
    .where((r) => r.isExpense)
    .fold(0.0, (sum, r) => sum + r.amount);

double monthIncome(List<Record> records) => records
    .where((r) => !r.isExpense)
    .fold(0.0, (sum, r) => sum + r.amount);

List<Record> weekRecords(DateTime weekStart) {
  final weekEnd = weekStart.add(const Duration(days: 6));
  return allRecords.value.where((r) {
    final d = r.date;
    return d.isAfter(weekStart.subtract(const Duration(days: 1))) &&
        d.isBefore(weekEnd.add(const Duration(days: 1))) &&
        r.bookId == currentBookId.value;
  }).toList();
}
