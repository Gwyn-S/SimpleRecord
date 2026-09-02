import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../utils/formatters.dart';
import 'month_year_picker.dart';

Future<DateTime?> showDatePickerSheet(BuildContext context, DateTime initial) {
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      clipBehavior: Clip.antiAlias,
      backgroundColor: colorBackgroundCard,
      child: _DatePickerSheet(initial: initial),
    ),
  );
}

class _DatePickerSheet extends StatefulWidget {
  final DateTime initial;

  const _DatePickerSheet({required this.initial});

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  static const _rowHeight = 44.0;

  late DateTime _baseMonth;
  late DateTime _month;
  late DateTime _selected;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _baseMonth = DateTime(_selected.year, _selected.month);
    _month = _baseMonth;
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _pageIndex =>
      (_month.year * 12 + _month.month) -
      (_baseMonth.year * 12 + _baseMonth.month);

  void _changeMonth(int delta) {
    final current = _pageController.page ?? _pageIndex.toDouble();
    _pageController.animateToPage(
      current.round() + delta,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _openMonthYearPicker() async {
    final target = await showMonthYearPicker(context, _month);
    if (target == null || !mounted) return;
    setState(() => _month = target);
    _pageController.jumpToPage(
      (target.year * 12 + target.month) -
          (_baseMonth.year * 12 + _baseMonth.month),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(themeColor),
            Padding(
              padding: const EdgeInsets.all(spacingL),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMonthNav(),
                  _buildWeekRow(),
                  _buildDayGrid(),
                  _buildActions(themeColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color themeColor) {
    final wd = '周${weekdaysShort[_selected.weekday - 1]}';
    return Container(
      width: double.infinity,
      color: themeColor,
      padding: const EdgeInsets.fromLTRB(
        spacingL,
        spacingM,
        spacingL,
        spacingM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_selected.year}年',
            style: TextStyle(
              fontSize: 14,
              color: colorTextOnPrimary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: spacingXXS),
          Text(
            '${_selected.month}月${_selected.day}日 $wd',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: colorTextOnPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNav() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _navButton('<', () => _changeMonth(-1)),
          GestureDetector(
            onTap: _openMonthYearPicker,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${_month.year}年${_month.month}月',
                style: textPickerItem,
              ),
            ),
          ),
          _navButton('>', () => _changeMonth(1)),
        ],
      ),
    );
  }

  Widget _navButton(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, color: colorTextSecondary),
        ),
      ),
    );
  }

  Widget _buildWeekRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: spacingXS),
      child: Row(
        children: weekdaysShort
            .map(
              (w) => Expanded(
                child: Center(child: Text(w, style: textCaption)),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDayGrid() {
    return SizedBox(
      height: 6 * _rowHeight,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: (page) {
            setState(() {
              _month = DateTime(_baseMonth.year, _baseMonth.month + page);
            });
          },
          itemBuilder: (context, page) => _buildMonthGrid(
            DateTime(_baseMonth.year, _baseMonth.month + page),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthGrid(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[];
    for (int i = 1; i < firstDay.weekday; i++) {
      cells.add(null);
    }
    for (int d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(month.year, month.month, d));
    }
    while (cells.length < 42) {
      cells.add(null);
    }
    return Column(
      children: List.generate(6, (row) {
        return SizedBox(
          height: _rowHeight,
          child: Row(
            children: cells
                .sublist(row * 7, row * 7 + 7)
                .map((d) => Expanded(child: _buildDayCell(d)))
                .toList(),
          ),
        );
      }),
    );
  }

  Widget _buildDayCell(DateTime? day) {
    if (day == null) return const SizedBox();
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final selected =
        day.year == _selected.year &&
        day.month == _selected.month &&
        day.day == _selected.day;
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    return GestureDetector(
      onTap: () => setState(() => _selected = day),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: selected
            ? Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: themeColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${day.day}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorTextOnPrimary,
                  ),
                ),
              )
            : SizedBox(
                width: 42,
                height: 42,
                child: Center(
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 16,
                      color: isToday ? themeColor : colorTextPrimary,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildActions(Color themeColor) {
    return Padding(
      padding: const EdgeInsets.only(top: spacingS),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _actionButton('取消', themeColor, () => Navigator.pop(context)),
          const SizedBox(width: spacingL),
          _actionButton(
            '确定',
            themeColor,
            () => Navigator.pop(context, _selected),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String text, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: spacingL,
          vertical: spacingS,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
