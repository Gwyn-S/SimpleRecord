import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../services/record_service.dart';
import '../utils/calendar_utils.dart';
import '../utils/formatters.dart';
import '../utils/lunar_utils.dart';
import '../utils/navigation.dart';
import '../widgets/home_top_bar.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late DateTime _currentMonth;
  DateTime? _selectedDay;
  late AnimationController _foldController;

  int _monthExpense = 0;
  int _monthIncome = 0;
  int _loadSeq = 0;

  final Map<int, Widget> _monthGridCache = {};
  int _selCacheKey = 0;

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _currentMonth = currentMonth.value;
    _pageController = PageController(initialPage: pageFromMonth(_currentMonth));
    _foldController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _load();
    recordsVersion.addListener(_load);
    currentLedgerId.addListener(_load);
    currentMonth.addListener(_onMonthChanged);
    themeColorNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    recordsVersion.removeListener(_load);
    currentLedgerId.removeListener(_load);
    currentMonth.removeListener(_onMonthChanged);
    themeColorNotifier.removeListener(_onThemeChanged);
    _foldController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (!mounted) return;
    _monthGridCache.clear();
    setState(() {});
  }

  Widget _monthGrid(DateTime month) {
    final page = pageFromMonth(month);
    final selected = _selectedDay;
    final selKey = selected == null
        ? 0
        : selected.year * 10000 + selected.month * 100 + selected.day;
    if (selKey != _selCacheKey) {
      _selCacheKey = selKey;
      _monthGridCache.clear();
    }
    return _monthGridCache.putIfAbsent(page, () => _buildMonthGrid(month));
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final records = await loadRecords(
      ledgerId: currentLedgerId.value,
      month: _currentMonth,
    );
    if (seq != _loadSeq || !mounted) return;
    setState(() {
      _monthIncome = monthIncome(records);
      _monthExpense = monthExpense(records);
    });
  }

  void _onMonthChanged() {
    if (!mounted) return;
    final m = currentMonth.value;
    if (m != _currentMonth) {
      _currentMonth = m;
      _pageController.jumpToPage(pageFromMonth(m));
    }
    _load();
    setState(() {});
  }

  String get _monthLabel => formatMonthLabel(_currentMonth);

  void _changeMonth(int delta) {
    final next = DateTime(_currentMonth.year, _currentMonth.month + delta);
    _pageController.animateToPage(
      pageFromMonth(next),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  int get _monthBalance => _monthIncome - _monthExpense;

  DateTime get _effectiveSelectedDay => _selectedDay ?? DateTime.now();

  int get _currentRowCount {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final totalCells = (firstDay.weekday - 1) + daysInMonth;
    return (totalCells + 6) ~/ 7;
  }

  int get _selectedRowIndex {
    final day = _effectiveSelectedDay;
    if (day.year != _currentMonth.year || day.month != _currentMonth.month) return 0;
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    return (firstDay.weekday - 1 + day.day - 1) ~/ 7;
  }

  double get _rowHeight => heightCalendarGrid / _currentRowCount;
  double get _maxOffset => heightCalendarGrid - _rowHeight;

  void _onVerticalDragStart(DragStartDetails details) {
    _foldController.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final deltaProgress = -details.delta.dy / _maxOffset;
    _foldController.value = (_foldController.value + deltaProgress).clamp(0.0, 1.0);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_maxOffset <= 0) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -200 || _foldController.value > 0.5) {
      _foldController.forward();
    } else {
      _foldController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Container(
        color: colorBackgroundPage,
      child: Column(
        children: [
          Builder(builder: (context) {
            final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
            return Container(
              color: themeColor,
              child: Column(
                children: [
                  SizedBox(height: MediaQuery.of(context).padding.top),
                  HomeTopBar(
                    monthLabel: _monthLabel,
                    onPrevMonth: () => _changeMonth(-1),
                    onNextMonth: () => _changeMonth(1),
                    onLedgerTap: () => openLedgerList(context),
                    onBackupTap: () => openBackup(context),
                    onSearchTap: () => openSearch(context),
                    onUserTap: () => openUser(context),
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
          }),
          Container(
              color: colorBackgroundCard,
              child: SizedBox(
                height: heightHeaderBar,
                child: Row(
                  children: [
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
              ),
            ),
            SizedBox(
              height: heightCalendarGrid,
              child: ValueListenableBuilder<double>(
                valueListenable: _foldController,
                builder: (context, t, _) {
                  final calendarHeight = heightCalendarGrid - t * _maxOffset;
                  final panelHeight = t * _maxOffset;
                  return Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: calendarHeight,
                        child: ClipRect(
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                height: calendarHeight,
                                child: Container(color: colorBackgroundCard),
                              ),
                              Positioned(
                                top: -t * _selectedRowIndex * _rowHeight,
                                left: 0,
                                right: 0,
                                height: heightCalendarGrid,
                                child: RepaintBoundary(
                                  child: Container(
                                    color: colorBackgroundCard,
                                    child: ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
                                        PointerDeviceKind.touch,
                                        PointerDeviceKind.mouse,
                                      }),
                                      child: PageView.builder(
                                        controller: _pageController,
                                        onPageChanged: (page) {
                                          final m = monthFromPage(page);
                                          _currentMonth = m;
                                          currentMonth.value = m;
                                          _load();
                                          setState(() {});
                                        },
                                        itemBuilder: (context, page) => _monthGrid(monthFromPage(page)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: calendarHeight,
                        left: 0,
                        right: 0,
                        height: panelHeight,
                        child: RepaintBoundary(child: _buildPanel()),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      color: colorBackgroundPage,
      child: const Center(
        child: Text('面板内容', style: TextStyle(color: colorTextPlaceholder)),
      ),
    );
  }

  Widget _summaryItem(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textSecondary.copyWith(color: colorTextOnPrimary)),
        const SizedBox(height: spacingXS),
        Text(formatAmount(value), style: textAmountMedium),
      ],
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
    final rowHeight = heightCalendarGrid / rowCount;

    return Container(
      color: colorBackgroundCard,
      child: Column(
        children: List.generate(rowCount, (i) {
          final rowCells = cells.sublist(i * 7, (i + 1) * 7);
          return SizedBox(
            height: rowHeight,
            child: Row(
              children: rowCells.map((day) => Expanded(child: _buildDayCell(day))).toList(),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayCell(DateTime? day) {
    if (day == null) return const SizedBox();

    final selected = _selectedDay != null &&
        day.year == _selectedDay!.year &&
        day.month == _selectedDay!.month &&
        day.day == _selectedDay!.day;

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
            color: selected
                ? Theme.of(context).extension<AppThemeColors>()!.primary
                : Colors.transparent,
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
