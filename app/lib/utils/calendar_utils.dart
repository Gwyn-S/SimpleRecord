import '../models/data/record.dart';

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
  final year = page ~/ 12;
  final month = page % 12 + 1;
  return DateTime(year, month);
}

int pageFromMonth(DateTime m) => m.year * 12 + m.month - 1;

int monthExpense(List<Record> records) =>
    records.where((r) => r.isExpense).fold(0, (sum, r) => sum + r.amountCents);

int monthIncome(List<Record> records) =>
    records.where((r) => !r.isExpense).fold(0, (sum, r) => sum + r.amountCents);
