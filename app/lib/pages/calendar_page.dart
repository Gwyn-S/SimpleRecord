import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../theme.dart';
import '../models/record.dart';
import '../widgets/record_item.dart';
import 'home_top_bar.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late final PageController _pageController;
  late DateTime _currentMonth;
  DateTime? _selectedDay;
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _pageController = PageController(initialPage: now.year * 12 + now.month - 1);
    allRecords.addListener(_setState);
  }

  @override
  void dispose() {
    allRecords.removeListener(_setState);
    _pageController.dispose();
    super.dispose();
  }

  void _setState() {
    if (mounted) setState(() {});
  }

  List<Record> get _records => allRecords.value;

  DateTime _monthFromPage(int page) {
    final year = (page + 1) ~/ 12;
    final month = (page + 1) % 12;
    return DateTime(year, month == 0 ? 12 : month);
  }

  int _pageFromMonth(DateTime m) => m.year * 12 + m.month - 1;

  List<Record> _recordsForDay(DateTime day) {
    return _records.where((r) =>
        r.date.year == day.year &&
        r.date.month == day.month &&
        r.date.day == day.day &&
        r.bookId == currentBookId.value).toList();
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  bool _isSelected(DateTime d) {
    if (_selectedDay == null) return false;
    return d.year == _selectedDay!.year &&
        d.month == _selectedDay!.month &&
        d.day == _selectedDay!.day;
  }

  String get _monthLabel =>
      '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}';

  void _changeMonth(int delta) {
    final next = DateTime(_currentMonth.year, _currentMonth.month + delta);
    _pageController.animateToPage(
      _pageFromMonth(next),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  List<Record> get _monthRecords {
    return _records.where((r) =>
        r.date.year == _currentMonth.year &&
        r.date.month == _currentMonth.month &&
        r.bookId == currentBookId.value).toList();
  }

  double get _monthExpense => _monthRecords
      .where((r) => r.isExpense)
      .fold(0.0, (sum, r) => sum + r.amount);

  double get _monthIncome => _monthRecords
      .where((r) => !r.isExpense)
      .fold(0.0, (sum, r) => sum + r.amount);

  double get _monthBalance => _monthIncome - _monthExpense;

  String _fmtAmt(double v) => v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) {
            return Container(
              color: color,
              child: Column(
                children: [
                  SizedBox(height: MediaQuery.of(context).padding.top),
                  HomeTopBar(
                    monthLabel: _monthLabel,
                    onPrevMonth: () => _changeMonth(-1),
                    onNextMonth: () => _changeMonth(1),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryItem('本月支出', _monthExpense),
                        const SizedBox(width: 24),
                        _summaryItem('本月收入', _monthIncome),
                        const SizedBox(width: 24),
                        _summaryItem('本月结余', _monthBalance),
                      ],
                    ),
                  ),
                  _buildWeekdayHeader(),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: Column(
            children: [
              SizedBox(
                height: 320,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                  }),
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (page) => setState(() {
                      _currentMonth = _monthFromPage(page);
                      _selectedDay = null;
                    }),
                    itemBuilder: (context, page) {
                      final month = _monthFromPage(page);
                      return _buildMonthGrid(month);
                    },
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
              Expanded(
                child: _selectedDay == null
                    ? const Center(
                        child: Text('点击日期查看记录', style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
                      )
                    : _buildDayRecords(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryItem(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white)),
        const SizedBox(height: 4),
        Text(_fmtAmt(value), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400, letterSpacing: -1, color: Colors.white)),
      ],
    );
  }

  Widget _buildWeekdayHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: _weekdayLabels.map((label) {
          return Expanded(
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xAAFFFFFF),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMonthGrid(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    int startWeekday = firstDay.weekday;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final cells = <DateTime?>[];
    for (int i = 1; i < startWeekday; i++) {
      cells.add(null);
    }
    for (int d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(month.year, month.month, d));
    }

    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      final rowCells = cells.sublist(i, (i + 7).clamp(0, cells.length));
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: rowCells.map((day) => Expanded(child: _buildDayCell(day))).toList(),
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(children: rows),
    );
  }

  Widget _buildDayCell(DateTime? day) {
    if (day == null) return const SizedBox(height: 44);

    final dayRecords = _recordsForDay(day);
    final hasData = dayRecords.isNotEmpty;
    final today = _isToday(day);
    final selected = _isSelected(day);
    final isCurrentMonth = day.month == _currentMonth.month;

    return GestureDetector(
      onTap: () => setState(() => _selectedDay = day),
      child: SizedBox(
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected
                    ? themeColorNotifier.value
                    : today
                        ? themeColorNotifier.value.withValues(alpha: 0.12)
                        : null,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: today || selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected
                      ? Colors.white
                      : today
                          ? themeColorNotifier.value
                          : isCurrentMonth
                              ? const Color(0xFF333333)
                              : const Color(0xFFCCCCCC),
                ),
              ),
            ),
            if (hasData)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (dayRecords.any((r) => !r.isExpense))
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (dayRecords.any((r) => r.isExpense))
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF44336),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildDayRecords() {
    final day = _selectedDay!;
    final records = _recordsForDay(day);
    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final dateStr = '${day.month}月${day.day}日 ${weekdays[(day.weekday - 1) % 7]}';

    final income = records.where((r) => !r.isExpense).fold(0.0, (s, r) => s + r.amount);
    final expense = records.where((r) => r.isExpense).fold(0.0, (s, r) => s + r.amount);

    if (records.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text(dateStr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF333333))),
                const Spacer(),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Text('当日无记录', style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(dateStr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF333333))),
              const Spacer(),
              if (income > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                      children: [
                        const TextSpan(text: '收入 '),
                        TextSpan(text: _fmtAmt(income), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4CAF50))),
                      ],
                    ),
                  ),
                ),
              if (expense > 0)
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                    children: [
                      const TextSpan(text: '支出 '),
                      TextSpan(text: _fmtAmt(expense), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFF44336))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              ...records.map((r) => RecordItem(record: r)),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}
