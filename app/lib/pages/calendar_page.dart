import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../theme.dart';
import '../models/record.dart';
import '../services/record_service.dart';
import '../utils/calendar_utils.dart';
import '../utils/formatters.dart';
import '../utils/lunar_utils.dart';
import '../widgets/home_top_bar.dart';

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
    _currentWeekStart = weekStart(now);
    _pageController = PageController(initialPage: pageFromMonth(_currentMonth));
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

  String get _monthLabel {
    if (_weekMode) {
      final start = _currentWeekStart ?? weekStart(_selectedOrToday());
      return formatMonthLabel(start);
    }
    return formatMonthLabel(_currentMonth);
  }

  void _changeMonth(int delta) {
    if (_weekMode) {
      _changeWeek(delta);
      return;
    }
    final next = DateTime(_currentMonth.year, _currentMonth.month + delta);
    _pageController.animateToPage(
      pageFromMonth(next),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  List<Record> get _monthRecords => monthRecords(_currentMonth);

  double get _monthExpense => monthExpense(_monthRecords);

  double get _monthIncome => monthIncome(_monthRecords);

  double get _monthBalance => _monthIncome - _monthExpense;

  DateTime _selectedOrToday() => _selectedDay ?? DateTime.now();

  void _changeWeek(int delta) {
    final currentStart = weekStart(_selectedOrToday());
    final next = currentStart.add(Duration(days: delta * 7));
    _pageController.animateToPage(
      weekPageFromDay(next),
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
    return heightCalendarGrid / rowCount;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colorBackgroundPage,
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
                      padding: const EdgeInsets.fromLTRB(spacingXXL, 0, spacingXXL, spacingS),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _summaryItem('本月支出', _monthExpense),
                          const SizedBox(width: spacingXXL),
                          _summaryItem('本月收入', _monthIncome),
                          const SizedBox(width: spacingXXL),
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
            color: colorBackgroundCard,
            child: _buildWeekdayHeader(),
          ),
          Container(
            color: colorBackgroundCard,
            height: _weekMode ? _monthRowHeight : heightCalendarGrid,
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
                    _currentWeekStart = dayFromWeekPage(page);
                  } else {
                    _currentMonth = monthFromPage(page);
                  }
                }),
                itemBuilder: (context, page) {
                  if (_weekMode) {
                    return _buildWeekGrid(dayFromWeekPage(page));
                  }
                  return _buildMonthGrid(monthFromPage(page));
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
        Text(label, style: textSecondary.copyWith(color: colorTextOnPrimary)),
        const SizedBox(height: spacingXS),
        Text(formatAmount(value), style: textAmountMedium),
      ],
    );
  }

  Widget _buildWeekdayHeader() {
    return SizedBox(
      height: heightHeaderBar,
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() => _weekMode = !_weekMode);
              _pageController.dispose();
              if (_weekMode) {
                final start = weekStart(_selectedOrToday());
                _currentWeekStart = start;
                _pageController = PageController(initialPage: weekPageFromDay(start));
              } else {
                _pageController = PageController(initialPage: pageFromMonth(_currentMonth));
              }
            },
            child: Container(
              width: sizeIconContainer,
              height: heightHeaderBar,
              alignment: Alignment.center,
              child: Icon(
                _weekMode ? Icons.calendar_view_month : Icons.view_week,
                size: iconSizeDefault,
                color: colorTextSecondary,
              ),
            ),
          ),
          ..._weekdayLabels.map((label) {
            return Expanded(
              child: Center(
                child: Text(
                  label,
                  style: textCaption,
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
      color: colorBackgroundCard,
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

  Widget _buildWeekGrid(DateTime ws) {
    final days = List.generate(7, (i) => ws.add(Duration(days: i)));
    final rowHeight = _monthRowHeight;

    return Container(
      color: colorBackgroundCard,
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

    // 获取农历信息
    final lunarText = LunarUtils.getDisplayText(day);
    final isSpecial = LunarUtils.isFestivalOrJieQi(day);

    return GestureDetector(
      onTap: () => setState(() => _selectedDay = day),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? themeColorNotifier.value : Colors.transparent,
            width: borderWidthDefault,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  const Spacer(flex: 1),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        '${day.day}'.padLeft(2, '0'),
                        style: textAmountBold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: lunarText.split('').map((char) => Text(
                        char,
                        style: isSpecial ? textLunarFestival : textLunarDay,
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: Column(
              children: const [
                Expanded(child: SizedBox()),
                Expanded(child: SizedBox()),
              ],
            )),
          ],
        ),
      ),
    );
  }
}
