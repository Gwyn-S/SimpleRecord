import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/record.dart';
import 'home_top_bar.dart';
import 'calendar_cell.dart';
import 'day_records_panel.dart';
import 'calendar_lunar_utils.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with SingleTickerProviderStateMixin {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay = DateTime.now();
  bool _slideToRight = true;
  late final AnimationController _slideCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 50),
  )..value = 1.0;

  Map<String, List<Record>> _bookRecordsCache = {};
  Map<String, ({double income, double expense})> _dayAmountsCache = {};
  List<Record> _monthRecordsCache = [];
  double _monthIncome = 0;
  double _monthExpense = 0;
  final Map<String, LunarInfo> _lunarCache = {};

  @override
  void initState() {
    super.initState();
    allRecords.addListener(_onRecordsChanged);
    _rebuildMonthCache();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    allRecords.removeListener(_onRecordsChanged);
    super.dispose();
  }

  void _onRecordsChanged() {
    if (!mounted) return;
    _rebuildMonthCache();
    setState(() {});
  }

  List<Record> get _records => allRecords.value;

  void _rebuildMonthCache() {
    final bid = currentBookId.value;
    _bookRecordsCache = {};
    for (final r in _records) {
      if (r.bookId != bid) continue;
      final key = '${r.date.year}-${r.date.month}';
      (_bookRecordsCache[key] ??= []).add(r);
    }
    _rebuildCurrentMonthData();
  }

  void _rebuildCurrentMonthData() {
    final key = '${_currentMonth.year}-${_currentMonth.month}';
    _monthRecordsCache = _bookRecordsCache[key] ?? [];
    _monthIncome = 0;
    _monthExpense = 0;
    _dayAmountsCache = {};

    for (final r in _monthRecordsCache) {
      if (r.isExpense) {
        _monthExpense += r.amount;
      } else {
        _monthIncome += r.amount;
      }
      final dayKey = '${r.date.day}';
      final prev = _dayAmountsCache[dayKey];
      double inc = r.isExpense ? 0 : r.amount;
      double exp = r.isExpense ? r.amount : 0;
      if (prev != null) {
        _dayAmountsCache[dayKey] = (income: prev.income + inc, expense: prev.expense + exp);
      } else {
        _dayAmountsCache[dayKey] = (income: inc, expense: exp);
      }
    }
  }

  void _prevMonth() {
    _slideToRight = true;
    _slideCtrl.forward(from: 0.0);
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      _selectedDay = null;
      _rebuildCurrentMonthData();
    });
  }

  void _nextMonth() {
    _slideToRight = false;
    _slideCtrl.forward(from: 0.0);
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      _selectedDay = null;
      _rebuildCurrentMonthData();
    });
  }

  ({double expense, double income}) _dayAmounts(DateTime day) {
    return _dayAmountsCache['${day.day}'] ?? (expense: 0.0, income: 0.0);
  }

  double get _monthBalance => _monthIncome - _monthExpense;

  List<Record> _recordsForDay(DateTime day) {
    return _monthRecordsCache.where((r) => r.date.day == day.day).toList();
  }

  LunarInfo _getLunarInfo(DateTime date) {
    final key = '${date.year}-${date.month}-${date.day}';
    return _lunarCache[key] ??= lunarInfo(date);
  }

  String _fmt(double v) => v.toStringAsFixed(2);

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
                    monthLabel: '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}',
                    onPrevMonth: _prevMonth,
                    onNextMonth: _nextMonth,
                  ),
                  _buildMonthSummary(),
                ],
              ),
            );
          },
        ),
        _buildWeekHeader(),
        Expanded(
          child: Column(
            children: [
              _buildCalendarGrid(),
              Expanded(
                child: DayRecordsPanel(
                  selectedDay: _selectedDay,
                  records: _selectedDay != null ? _recordsForDay(_selectedDay!) : [],
                  dayIncome: _selectedDay != null ? _dayAmounts(_selectedDay!).income : 0,
                  dayExpense: _selectedDay != null ? _dayAmounts(_selectedDay!).expense : 0,
                  fmt: _fmt,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Row(
        children: [
          _summaryItem('本月收入', _fmt(_monthIncome)),
          const SizedBox(width: 40),
          _summaryItem('本月支出', _fmt(_monthExpense)),
          const SizedBox(width: 40),
          _summaryItem('本月结余', _fmt(_monthBalance)),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String amount) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white)),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('¥', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white)),
              const SizedBox(width: 4),
              Text(amount, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400, letterSpacing: -1, color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeekHeader() {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      color: Colors.white,
      child: Row(
        children: weekdays.map((d) => Expanded(
          child: Center(
            child: Text(d, style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF999999),
            )),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final startWeekday = (firstDay.weekday - 1) % 7;
    final totalDays = lastDay.day;
    final today = DateTime.now();
    final totalCount = startWeekday + totalDays;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: Container(
        color: Colors.white,
        child: AnimatedBuilder(
          animation: _slideCtrl,
          builder: (context, child) {
            final offset = Tween<double>(
              begin: _slideToRight ? -1.0 : 1.0,
              end: 0.0,
            ).evaluate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
            return Transform.translate(
              offset: Offset(offset * MediaQuery.of(context).size.width, 0),
              child: child,
            );
          },
          child: GridView.builder(
            key: ValueKey(_currentMonth),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 0,
              crossAxisSpacing: 0,
              childAspectRatio: 0.85,
            ),
            itemCount: totalCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              if (index < startWeekday) return const SizedBox();
              final day = index - startWeekday + 1;
              final date = DateTime(_currentMonth.year, _currentMonth.month, day);
              final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
              final isSelected = _selectedDay != null &&
                  date.year == _selectedDay!.year && date.month == _selectedDay!.month && date.day == _selectedDay!.day;
              final amounts = _dayAmounts(date);

              return CalendarCell(
                date: date,
                isToday: isToday,
                isSelected: isSelected,
                expense: amounts.expense,
                income: amounts.income,
                lunar: _getLunarInfo(date),
                onTap: () => setState(() => _selectedDay = date),
              );
            },
          ),
        ),
      ),
    );
  }
}
