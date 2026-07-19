import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../theme.dart';
import '../models/record.dart';
import 'home_top_bar.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late PageController _pageController;
  late DateTime _currentMonth;
  DateTime? _selectedDay;
  DateTime? _currentWeekStart;
  bool _weekMode = false;
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _currentWeekStart = _weekStart(now);
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

  String get _monthLabel {
    if (_weekMode) {
      final start = _currentWeekStart ?? _weekStart(_selectedOrToday());
      return '${start.year}-${start.month.toString().padLeft(2, '0')}';
    }
    return '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}';
  }

  void _changeMonth(int delta) {
    if (_weekMode) {
      _changeWeek(delta);
      return;
    }
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

  DateTime _selectedOrToday() => _selectedDay ?? DateTime.now();

  DateTime _weekStart(DateTime day) {
    return day.subtract(Duration(days: day.weekday - 1));
  }

  static final DateTime _epochMonday = DateTime(2020, 1, 6);

  int _weekPageFromDay(DateTime day) {
    final start = _weekStart(day);
    return start.difference(_epochMonday).inDays ~/ 7;
  }

  DateTime _dayFromWeekPage(int page) {
    return _epochMonday.add(Duration(days: page * 7));
  }

  void _changeWeek(int delta) {
    final currentStart = _weekStart(_selectedOrToday());
    final next = currentStart.add(Duration(days: delta * 7));
    _pageController.animateToPage(
      _weekPageFromDay(next),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  double get _monthRowHeight {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    int startWeekday = firstDay.weekday;
    final totalCells = startWeekday - 1 + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    return 360.0 / rowCount;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: scaffoldBackground,
      child: Column(
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
                  ],
                ),
              );
            },
          ),
          Container(
            color: Colors.white,
            child: _buildWeekdayHeader(),
          ),
          Container(
            color: Colors.white,
            height: _weekMode ? _monthRowHeight : 360,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              }),
              child: PageView.builder(
                key: ValueKey(_weekMode),
                controller: _pageController,
                onPageChanged: (page) => setState(() {
                  if (_weekMode) {
                    _currentWeekStart = _dayFromWeekPage(page);
                  } else {
                    _currentMonth = _monthFromPage(page);
                  }
                }),
                itemBuilder: (context, page) {
                  if (_weekMode) {
                    return _buildWeekGrid(_dayFromWeekPage(page));
                  }
                  return _buildMonthGrid(_monthFromPage(page));
                },
              ),
            ),
          ),
        ],
      ),
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
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() => _weekMode = !_weekMode);
              _pageController.dispose();
              if (_weekMode) {
                final start = _weekStart(_selectedOrToday());
                _currentWeekStart = start;
                _pageController = PageController(initialPage: _weekPageFromDay(start));
              } else {
                _pageController = PageController(initialPage: _pageFromMonth(_currentMonth));
              }
            },
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: Icon(
                _weekMode ? Icons.calendar_view_month : Icons.view_week,
                size: 20,
                color: const Color(0xFF999999),
              ),
            ),
          ),
          ..._weekdayLabels.map((label) {
            return Expanded(
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF999999),
                  ),
                ),
              ),
            );
          }),
        ],
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
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    final rowCount = cells.length ~/ 7;

    return Container(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rowHeight = constraints.maxHeight / rowCount;
          final rows = <Widget>[];
          for (int i = 0; i < cells.length; i += 7) {
            final rowCells = cells.sublist(i, (i + 7).clamp(0, cells.length));
            rows.add(SizedBox(
              height: rowHeight,
              child: Row(
                children: rowCells.map((day) => Expanded(child: _buildDayCell(day))).toList(),
              ),
            ));
          }
          return Column(children: rows);
        },
      ),
    );
  }

  Widget _buildWeekGrid(DateTime weekStart) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final rowHeight = _monthRowHeight;

    return Container(
      color: Colors.white,
      child: SizedBox(
        height: rowHeight,
        child: Row(
          children: days.map((day) => Expanded(child: _buildDayCell(day))).toList(),
        ),
      ),
    );
  }

  Widget _buildDayCell(DateTime? day) {
    if (day == null) return const SizedBox();

    final selected = _selectedDay != null &&
        day.year == _selectedDay!.year &&
        day.month == _selectedDay!.month &&
        day.day == _selectedDay!.day;

    return GestureDetector(
      onTap: () => setState(() => _selectedDay = day),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? themeColorNotifier.value : Colors.transparent,
            width: 1,
          ),
        ),
        alignment: const Alignment(0, -0.8),
        child: Text(
          '${day.day}'.padLeft(2, '0'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF333333),
          ),
        ),
      ),
    );
  }
}
