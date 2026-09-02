import '../models/record.dart';
import '../services/record_service.dart';
import '../utils/formatters.dart';

/// 统计数据类型
enum StatsRange { week, month, year, custom }

/// 统计数据缓存键
class StatsCacheKey {
  final StatsRange range;
  final int index;
  final int year;
  final String? ledgerId;
  final DateTime? customStart;
  final DateTime? customEnd;

  const StatsCacheKey({
    required this.range,
    required this.index,
    required this.year,
    this.ledgerId,
    this.customStart,
    this.customEnd,
  });

  @override
  String toString() =>
      '${ledgerId ?? 'none'}-$range-$index-$year-'
      '${customStart != null ? toEpochDay(customStart!) : ''}-'
      '${customEnd != null ? toEpochDay(customEnd!) : ''}';
}

/// 统计数据结果
class StatsData {
  final int totalExpense;
  final int totalIncome;
  final List<({String categoryName, int amountCents, int count})>
  expenseByCategory;
  final List<({String label, int amountCents})> periodData;
  final List<({String label, int amountCents})> weekSummary;
  final List<({String label, int amountCents})> monthSummary;
  final List<({String label, int amountCents})> yearSummary;

  const StatsData({
    required this.totalExpense,
    required this.totalIncome,
    required this.expenseByCategory,
    required this.periodData,
    required this.weekSummary,
    required this.monthSummary,
    required this.yearSummary,
  });
}

({DateTime jan1Monday, DateTime currentMonday, int currentWeek}) _weekInfo() {
  final now = DateTime.now();
  final jan1 = DateTime(now.year, 1, 1);
  final jan1Monday = jan1.subtract(Duration(days: jan1.weekday - 1));
  final currentMonday = now.subtract(Duration(days: now.weekday - 1));
  final currentWeek =
      ((currentMonday.difference(jan1Monday).inDays) / 7).floor() + 1;
  return (
    jan1Monday: jan1Monday,
    currentMonday: currentMonday,
    currentWeek: currentWeek,
  );
}

/// 计算日期范围
({DateTime start, DateTime end})? getDateRange({
  required StatsRange range,
  required int index,
  required int year,
  required int totalItems,
  required DateTime customStart,
  required DateTime customEnd,
}) {
  final now = DateTime.now();
  switch (range) {
    case StatsRange.week:
      final wi = _weekInfo();
      final weekOffset = totalItems - 1 - index;
      final targetWeek = wi.currentWeek - weekOffset;
      final weekStart = wi.jan1Monday.add(Duration(days: (targetWeek - 1) * 7));
      final weekEnd = weekStart.add(const Duration(days: 7));
      return (start: weekStart, end: weekEnd);
    case StatsRange.month:
      final monthOffset = totalItems - 1 - index;
      final targetMonth = now.month - monthOffset;
      final start = DateTime(year, targetMonth, 1);
      final end = DateTime(year, targetMonth + 1, 0);
      return (start: start, end: end);
    case StatsRange.year:
      final yearOffset = totalItems - 1 - index;
      final targetYear = year - yearOffset;
      final start = DateTime(targetYear, 1, 1);
      final end = DateTime(targetYear + 1, 1, 1);
      return (start: start, end: end);
    case StatsRange.custom:
      return (start: customStart, end: customEnd);
  }
}

/// 加载统计数据
Future<StatsData?> loadStatsData({
  required StatsRange range,
  required int index,
  required int year,
  required int totalItems,
  required DateTime customStart,
  required DateTime customEnd,
}) async {
  final dateRange = getDateRange(
    range: range,
    index: index,
    year: year,
    totalItems: totalItems,
    customStart: customStart,
    customEnd: customEnd,
  );
  if (dateRange == null) return null;

  final ledgerId = currentLedgerId.value;
  if (ledgerId == null) return null;

  // 周/月 tab 需要全年数据来计算汇总
  DateTime loadStart;
  DateTime loadEnd;
  switch (range) {
    case StatsRange.week:
    case StatsRange.month:
      loadStart = DateTime(year, 1, 1);
      loadEnd = DateTime(year + 1, 1, 1);
      break;
    case StatsRange.year:
      loadStart = DateTime(year - 5, 1, 1);
      loadEnd = DateTime(year + 1, 1, 1);
      break;
    case StatsRange.custom:
      loadStart = dateRange.start;
      loadEnd = dateRange.end;
      break;
  }

  final results = await Future.wait([
    loadRecordsByDateRange(ledgerId: ledgerId, start: loadStart, end: loadEnd),
    loadExpenseByCategory(
      ledgerId: ledgerId,
      start: dateRange.start,
      end: dateRange.end,
    ),
  ]);

  final records = results[0] as List<Record>;
  final expenseByCategory =
      results[1] as List<({String categoryName, int amountCents, int count})>;

  // 只统计当前所选区间内的记录。
  // loadStart/loadEnd 是为下方的周/月/年汇总图按更大范围取数，
  // 总额须按 dateRange（如本周/本月）过滤，避免混入区间外数据。
  final dStart = dateRange.start;
  final dEnd = dateRange.end;
  int totalExpense = 0;
  int totalIncome = 0;
  for (final r in records) {
    if (r.date.isBefore(dStart) || !r.date.isBefore(dEnd)) continue;
    if (r.isExpense) {
      totalExpense += r.amountCents;
    } else {
      totalIncome += r.amountCents;
    }
  }

  return StatsData(
    totalExpense: totalExpense,
    totalIncome: totalIncome,
    expenseByCategory: expenseByCategory,
    periodData: _buildPeriodData(records, range, dateRange),
    weekSummary: _buildWeekSummaryData(records),
    monthSummary: _buildMonthSummaryData(records),
    yearSummary: _buildYearSummaryData(records),
  );
}

List<({String label, int amountCents})> _buildPeriodData(
  List<Record> records,
  StatsRange range,
  ({DateTime start, DateTime end})? dateRange,
) {
  if (dateRange == null) return [];

  DateTime start;
  int days;
  String Function(DateTime) labelFn;

  switch (range) {
    case StatsRange.week:
      start = dateRange.start;
      days = dateRange.end.difference(dateRange.start).inDays;
      labelFn = (d) =>
          '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
      break;
    case StatsRange.month:
      start = dateRange.start;
      days = dateRange.end.difference(dateRange.start).inDays + 1;
      labelFn = (d) => d.day.toString().padLeft(2, '0');
      break;
    case StatsRange.year:
      start = dateRange.start;
      days = dateRange.end.difference(dateRange.start).inDays + 1;
      labelFn = (d) =>
          '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
      break;
    case StatsRange.custom:
      start = dateRange.start;
      days = dateRange.end.difference(dateRange.start).inDays + 1;
      labelFn = (d) =>
          '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
      break;
  }

  final dailyExpense = List.filled(days, 0);
  final startEpoch = toEpochDay(start);
  for (final r in records) {
    if (!r.isExpense) continue;
    final dayIndex = toEpochDay(r.date) - startEpoch;
    if (dayIndex >= 0 && dayIndex < days) {
      dailyExpense[dayIndex] += r.amountCents;
    }
  }

  return List.generate(days, (i) {
    final date = start.add(Duration(days: i));
    return (label: labelFn(date), amountCents: dailyExpense[i]);
  });
}

List<({String label, int amountCents})> _buildWeekSummaryData(
  List<Record> records,
) {
  final wi = _weekInfo();
  final weeklyExpense = List.filled(wi.currentWeek, 0);
  for (final r in records) {
    if (!r.isExpense) continue;
    final rMonday = DateTime(
      r.date.year,
      r.date.month,
      r.date.day,
    ).subtract(Duration(days: r.date.weekday - 1));
    final weekIndex = ((rMonday.difference(wi.jan1Monday).inDays) / 7).floor();
    if (weekIndex >= 0 && weekIndex < wi.currentWeek) {
      weeklyExpense[weekIndex] += r.amountCents;
    }
  }
  return List.generate(wi.currentWeek, (i) {
    final isLastWeek = i == wi.currentWeek - 2;
    final isThisWeek = i == wi.currentWeek - 1;
    final label = isThisWeek
        ? '本周'
        : isLastWeek
        ? '上周'
        : '${i + 1}周';
    return (label: label, amountCents: weeklyExpense[i]);
  });
}

List<({String label, int amountCents})> _buildMonthSummaryData(
  List<Record> records,
) {
  final now = DateTime.now();
  final monthlyExpense = List.filled(now.month, 0);
  for (final r in records) {
    if (!r.isExpense) continue;
    final monthIndex = r.date.month - 1;
    if (monthIndex >= 0 && monthIndex < now.month) {
      monthlyExpense[monthIndex] += r.amountCents;
    }
  }
  return List.generate(now.month, (i) {
    final isLastMonth = i == now.month - 2;
    final isThisMonth = i == now.month - 1;
    final label = isThisMonth
        ? '本月'
        : isLastMonth
        ? '上月'
        : '${i + 1}月';
    return (label: label, amountCents: monthlyExpense[i]);
  });
}

List<({String label, int amountCents})> _buildYearSummaryData(
  List<Record> records,
) {
  final now = DateTime.now();
  final startYear = now.year - 5;
  const yearCount = 6;
  final yearlyExpense = List.filled(yearCount, 0);
  for (final r in records) {
    if (!r.isExpense) continue;
    final yearIndex = r.date.year - startYear;
    if (yearIndex >= 0 && yearIndex < yearCount) {
      yearlyExpense[yearIndex] += r.amountCents;
    }
  }
  return List.generate(yearCount, (i) {
    final year = startYear + i;
    final label = year == now.year
        ? '今年'
        : year == now.year - 1
        ? '去年'
        : year == now.year - 2
        ? '前年'
        : '$year';
    return (label: label, amountCents: yearlyExpense[i]);
  });
}

/// 获取时间标签列表
List<String> getRangeLabels(StatsRange range, DateTime customPreset) {
  final now = DateTime.now();
  switch (range) {
    case StatsRange.week:
      final wi = _weekInfo();
      return [for (var i = 1; i <= wi.currentWeek - 1; i++) '$i周', '上周', '本周'];
    case StatsRange.month:
      return [for (var i = 1; i <= now.month - 2; i++) '$i月', '上月', '本月'];
    case StatsRange.year:
      final y = now.year;
      return ['${y - 5}', '${y - 4}', '${y - 3}', '前年', '去年', '今年'];
    case StatsRange.custom:
      return ['自定义'];
  }
}
