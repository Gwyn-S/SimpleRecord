import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../models/record.dart';
import '../services/ledger_service.dart';
import '../services/record_service.dart';
import '../utils/calendar_utils.dart';
import '../utils/formatters.dart';
import '../utils/lunar_utils.dart';
import '../utils/navigation.dart';
import '../widgets/day_card.dart';
import '../widgets/home_top_bar.dart';
import '../widgets/month_year_picker.dart';
import '../widgets/record_item.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late PageController _weekPageController;
  late DateTime _currentMonth;
  DateTime? _selectedDay;
  late AnimationController _foldController;
  int? _viewedWeekPage; // 周视图当前浏览的页
  bool _wasFolded = false; // 是否处于折叠（周视图）状态
  bool _folded = false; // 当前是否为折叠完成的周视图状态
  bool _pendingWeekJump = false; // 从月视图切到周视图时需重新定位到选中周
  bool _pendingMonthJump = false; // 从周视图切回月视图时需重新定位到当前月

  int _monthExpense = 0;
  int _monthIncome = 0;
  int _loadSeq = 0;
  bool _isShared = false;
  final Map<String, int> _dayExpense = {};
  final Map<String, int> _dayIncome = {};
  final Map<String, List<Record>> _dayRecords = {};

  final Map<int, Widget> _monthGridCache = {};
  int _selCacheKey = 0;

  @override
  void initState() {
    super.initState();
    _currentMonth = currentMonth.value;
    _selectedDay = DateTime.now();
    _pageController = PageController(initialPage: pageFromMonth(_currentMonth));
    _weekPageController = PageController(initialPage: _foldWeekPage);
    _foldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _foldController.addListener(_onFoldTick);
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
    _foldController.removeListener(_onFoldTick);
    _foldController.dispose();
    _pageController.dispose();
    _weekPageController.dispose();
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
    final grid = _monthGridCache.putIfAbsent(
      page,
      () => _buildMonthGrid(month),
    );
    // 只保留相邻 3 个月，翻页时逐页淘汰远处条目，避免长期累积
    _monthGridCache.removeWhere((key, _) => (key - page).abs() > 1);
    return grid;
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final records = await loadRecords(
      ledgerId: currentLedgerId.value,
      month: _currentMonth,
    );
    var shared = false;
    for (final l in await loadLedgers()) {
      if (l.id == currentLedgerId.value) {
        shared = l.syncMode == 1;
        break;
      }
    }
    if (seq != _loadSeq || !mounted) return;
    setState(() {
      _isShared = shared;
      _monthIncome = monthIncome(records);
      _monthExpense = monthExpense(records);
      _dayExpense.clear();
      _dayIncome.clear();
      _dayRecords.clear();
      for (final r in records) {
        final key = '${r.date.year}-${r.date.month}-${r.date.day}';
        _dayRecords.putIfAbsent(key, () => []).add(r);
        if (r.isExpense) {
          _dayExpense[key] = (_dayExpense[key] ?? 0) + r.amountCents;
        } else {
          _dayIncome[key] = (_dayIncome[key] ?? 0) + r.amountCents;
        }
      }
      _monthGridCache.clear();
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

  Future<void> _openMonthPicker(BuildContext context) async {
    final target = await showMonthYearPicker(context, _currentMonth);
    if (target == null || !mounted) return;
    if (target.year == _currentMonth.year &&
        target.month == _currentMonth.month) {
      return;
    }
    setState(() {
      _currentMonth = target;
    });
    _pageController.jumpToPage(pageFromMonth(target));
    currentMonth.value = target;
    if (_foldController.value > 0.99) {
      _foldController.reverse();
    }
  }

  int get _monthBalance => _monthIncome - _monthExpense;

  DateTime get _effectiveSelectedDay => _selectedDay ?? DateTime.now();

  int get _foldWeekPage {
    final sel = _selectedDay;
    if (sel != null &&
        sel.year == _currentMonth.year &&
        sel.month == _currentMonth.month) {
      return weekPageFromDay(sel);
    }
    return weekPageFromDay(
      DateTime(_currentMonth.year, _currentMonth.month, 1),
    );
  }

  int get _currentRowCount {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final totalCells = (firstDay.weekday - 1) + daysInMonth;
    return (totalCells + 6) ~/ 7;
  }

  int get _selectedRowIndex {
    final day = _effectiveSelectedDay;
    if (day.year != _currentMonth.year || day.month != _currentMonth.month) {
      return 0;
    }
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    return (firstDay.weekday - 1 + day.day - 1) ~/ 7;
  }

  double get _rowHeight =>
      heightCalendarGrid / (_currentRowCount < 5 ? 5 : _currentRowCount);
  double get _weekViewHeight => heightCalendarGrid / 5;
  double get _maxOffset => heightCalendarGrid - _weekViewHeight;

  void _onVerticalDragStart(DragStartDetails details) {
    _foldController.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final deltaProgress = -details.delta.dy / _maxOffset;
    _foldController.value = (_foldController.value + deltaProgress).clamp(
      0.0,
      1.0,
    );
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
            Builder(
              builder: (context) {
                final themeColor = Theme.of(
                  context,
                ).extension<AppThemeColors>()!.primary;
                return Container(
                  color: themeColor,
                  child: Column(
                    children: [
                      SizedBox(height: MediaQuery.of(context).padding.top),
                      HomeTopBar(
                        monthLabel: _monthLabel,
                        onPrevMonth: () => _changeMonth(-1),
                        onNextMonth: () => _changeMonth(1),
                        onMonthLabelTap: () => _openMonthPicker(context),
                        onLedgerTap: () => openLedgerList(context),
                        onBackupTap: () => openBackup(context),
                        onSearchTap: () => openSearch(context),
                        onUserTap: () => openUser(context),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          spacingXXL,
                          0,
                          spacingXXL,
                          spacingS,
                        ),
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
              child: SizedBox(
                height: heightHeaderBar,
                child: Row(
                  children: [
                    ...weekdaysShort.map((label) {
                      return Expanded(
                        child: Center(child: Text(label, style: textCaption)),
                      );
                    }),
                  ],
                ),
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: _foldController,
              builder: (context, t, _) {
                final calendarHeight = heightCalendarGrid - t * _maxOffset;
                return SizedBox(
                  height: calendarHeight,
                  child: ClipRect(
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: Container(color: colorBackgroundCard),
                        ),
                        Positioned(
                          top: t >= 0.999
                              ? 0
                              : -t * _selectedRowIndex * _rowHeight,
                          left: 0,
                          right: 0,
                          height: t >= 0.999
                              ? calendarHeight
                              : heightCalendarGrid,
                          child: RepaintBoundary(
                            child: Container(
                              color: colorBackgroundCard,
                              child: t >= 0.999
                                  ? _buildWeekView()
                                  : _buildMonthPageView(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Expanded(child: _buildPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel() {
    final day = _selectedDay;
    if (day == null) {
      return const SizedBox();
    }
    final key = '${day.year}-${day.month}-${day.day}';
    final records = _dayRecords[key] ?? [];
    if (records.isEmpty) {
      return Container(color: colorBackgroundPage);
    }
    return Container(
      color: colorBackgroundPage,
      padding: const EdgeInsets.only(top: 12),
      child: NotificationListener<OverscrollNotification>(
        onNotification: (n) {
          if (_folded && n.overscroll < 0) {
            _foldController.reverse();
            return true;
          }
          return false;
        },
        child: ListView(
          physics: _folded
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: spacingS),
          children: [
            DayCard(
              dayRecords: records,
              headerDate: day,
              expanded: true,
              isShared: _isShared,
              recordBuilder: (context, r) => RecordItem(
                record: r,
                onEdit: () => openEditRecord(context, r),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthPageView() {
    _pendingWeekJump = true;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      child: PageView.builder(
        key: const ValueKey('month_pager'),
        controller: _pageController,
        onPageChanged: (page) {
          final m = monthFromPage(page);
          if (m != _currentMonth) {
            _currentMonth = m;
            currentMonth.value = m;
          }
        },
        itemBuilder: (context, page) => _monthGrid(monthFromPage(page)),
      ),
    );
  }

  Widget _buildWeekView() {
    _pendingMonthJump = true;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      child: PageView.builder(
        key: const ValueKey('week_pager'),
        controller: _weekPageController,
        onPageChanged: _onWeekPageChanged,
        itemBuilder: (context, page) {
          final monday = dayFromWeekPage(page);
          return Container(
            color: colorBackgroundCard,
            height: _weekViewHeight,
            child: Row(
              children: List.generate(7, (i) {
                return Expanded(
                  child: _buildDayCell(monday.add(Duration(days: i))),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  void _onWeekPageChanged(int page) {
    // 横向滑动只记录当前浏览的周，不改变选中日期（选中仅在收起周视图时确定）
    _viewedWeekPage = page;
    final m = dayFromWeekPage(page);
    final month = DateTime(m.year, m.month);
    if (month != _currentMonth) {
      _currentMonth = month;
      if (month != currentMonth.value) {
        currentMonth.value = month;
      }
      setState(() {});
    }
  }

  void _onFoldTick() {
    final t = _foldController.value;
    final nowFolded = t >= 0.999;
    if (nowFolded != _folded) {
      if (nowFolded) {
        // 折叠完成切入周视图：重建 week controller 直接定位选中周，
        // 避免周 PageView 从旧初始页先显示再跳转的抖动。
        if (_pendingWeekJump) {
          _pendingWeekJump = false;
          final targetPage = _foldWeekPage;
          _viewedWeekPage = targetPage;
          _weekPageController.dispose();
          _weekPageController = PageController(initialPage: targetPage);
        }
      } else {
        // 展开完成切回月视图：重建 month controller 直接定位当前月。
        if (_pendingMonthJump) {
          _pendingMonthJump = false;
          _pageController.dispose();
          _pageController = PageController(
            initialPage: pageFromMonth(_currentMonth),
          );
        }
      }
      setState(() => _folded = nowFolded);
    }
    if (nowFolded) {
      _wasFolded = true;
    } else if (t < 0.999 && _wasFolded) {
      _wasFolded = false;
      final viewed = _viewedWeekPage;
      if (viewed != null && viewed != _foldWeekPage) {
        setState(() => _selectedDay = dayFromWeekPage(viewed));
      }
    }
  }

  Widget _summaryItem(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textSecondary.copyWith(color: colorTextOnPrimary)),
        const SizedBox(height: spacingXS),
        Text(formatAmount(value), style: textAmountStat),
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
    final rowHeight = heightCalendarGrid / (rowCount < 5 ? 5 : rowCount);

    return Container(
      color: colorBackgroundCard,
      child: Column(
        children: List.generate(rowCount, (i) {
          final rowCells = cells.sublist(i * 7, (i + 1) * 7);
          return SizedBox(
            height: rowHeight,
            child: Row(
              children: rowCells
                  .map((day) => Expanded(child: _buildDayCell(day)))
                  .toList(),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayCell(DateTime? day) {
    if (day == null) return const SizedBox();

    final selected =
        _selectedDay != null &&
        day.year == _selectedDay!.year &&
        day.month == _selectedDay!.month &&
        day.day == _selectedDay!.day;

    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;

    final lunarText = LunarUtils.getDisplayText(day);
    final isSpecial = LunarUtils.isFestivalOrJieQi(day);

    final primary = Theme.of(context).extension<AppThemeColors>()!.primary;
    final dayKey = '${day.year}-${day.month}-${day.day}';
    final dayExp = _dayExpense[dayKey] ?? 0;
    final dayInc = _dayIncome[dayKey] ?? 0;

    return GestureDetector(
      onTap: () => setState(() => _selectedDay = day),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isToday ? colorTodayBackground : null,
          border: Border.all(
            color: selected ? primary : Colors.transparent,
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
                      children: lunarText
                          .split('')
                          .map(
                            (char) => Text(
                              char,
                              style: isSpecial
                                  ? textLunarFestival
                                  : textLunarDay,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: dayInc > 0
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '+${(dayInc / 100).round()}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: primary,
                              ),
                            ),
                          )
                        : const SizedBox(),
                  ),
                  Expanded(
                    child: dayExp > 0
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '-${(dayExp / 100).round()}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: colorExpense,
                              ),
                            ),
                          )
                        : const SizedBox(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
