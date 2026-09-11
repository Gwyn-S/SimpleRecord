import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../services/core/theme_service.dart';
import '../../utils/formatters.dart';
import '../../utils/toast.dart';
import '../common/date_picker_sheet.dart';

/// 日期筛选弹窗：两行快捷范围（本周/上周/本月/上月、近三月/近半年/今年/去年）
/// + 自定义起止日期，底部"不限/确定"。
/// 返回 (开始, 结束) 均非空为生效筛选；(null, null) 为不限；null 为取消。
class DateFilterSheet extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;

  const DateFilterSheet({super.key, this.initialStart, this.initialEnd});

  @override
  State<DateFilterSheet> createState() => _DateFilterSheetState();
}

class _DateFilterSheetState extends State<DateFilterSheet> {
  DateTime? _start;
  DateTime? _end;
  String? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _selectedPreset = widget.initialStart != null && widget.initialEnd != null
        ? matchPresetName(widget.initialStart!, widget.initialEnd!)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final presets = datePresets(DateTime.now());
    return Dialog(
      backgroundColor: colorBackgroundCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          spacingL,
          spacingM,
          spacingL,
          spacingS,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPresetRow(presets.sublist(0, 4), themeColor),
            const SizedBox(height: spacingS),
            _buildPresetRow(presets.sublist(4, 8), themeColor),
            const SizedBox(height: spacingM),
            _buildCustomRange(themeColor),
            const SizedBox(height: spacingM),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _actionButton(
                  '不限',
                  colorBackgroundInput,
                  colorTextPrimary,
                  () => Navigator.pop(context, (null, null)),
                ),
                const SizedBox(width: spacingS),
                _actionButton('确定', themeColor, colorTextOnPrimary, () {
                  if (_start == null || _end == null) {
                    showToast(context, '请选择开始和结束日期');
                    return;
                  }
                  Navigator.pop(context, (_start, _end));
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetRow(
    List<({String label, DateTime start, DateTime end})> row,
    Color themeColor,
  ) {
    return Row(
      children: [
        for (final p in row)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: p == row.last ? 0 : spacingS),
              child: _presetButton(p, themeColor),
            ),
          ),
      ],
    );
  }

  Widget _presetButton(
    ({String label, DateTime start, DateTime end}) preset,
    Color themeColor,
  ) {
    final selected = _selectedPreset == preset.label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _selectedPreset = preset.label;
        _start = preset.start;
        _end = preset.end;
      }),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? themeColor : colorBackgroundInput,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        child: Text(
          preset.label,
          style: TextStyle(
            fontSize: 14,
            color: selected ? colorTextOnPrimary : colorTextPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomRange(Color themeColor) {
    return Row(
      children: [
        Expanded(child: _dateField('开始日期', _start, isStart: true)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: spacingS),
          child: Text('至', style: textBody),
        ),
        Expanded(child: _dateField('结束日期', _end, isStart: false)),
      ],
    );
  }

  Widget _dateField(String hint, DateTime? value, {required bool isStart}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final picked = await showDatePickerSheet(
          context,
          value ?? DateTime.now(),
        );
        if (picked == null || !mounted) return;
        setState(() {
          _selectedPreset = null;
          if (isStart) {
            _start = DateTime(picked.year, picked.month, picked.day);
          } else {
            _end = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
          }
        });
      },
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorBackgroundInput,
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        child: Text(
          value == null ? hint : formatDateYmd(value),
          style: TextStyle(
            fontSize: 14,
            color: value == null ? colorTextSecondary : colorTextPrimary,
          ),
        ),
      ),
    );
  }

  Widget _actionButton(String text, Color bg, Color fg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: spacingM, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        child: Text(text, style: TextStyle(fontSize: 14, color: fg)),
      ),
    );
  }
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 8 个快捷日期范围（相对当天）。
List<({String label, DateTime start, DateTime end})> datePresets(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
  final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
  final thisMonthStart = DateTime(now.year, now.month, 1);
  final lastMonthStart = DateTime(now.year, now.month - 1, 1);
  DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
  return [
    (
      label: '本周',
      start: thisWeekStart,
      end: endOfDay(thisWeekStart.add(const Duration(days: 6))),
    ),
    (
      label: '上周',
      start: lastWeekStart,
      end: endOfDay(thisWeekStart.subtract(const Duration(days: 1))),
    ),
    (
      label: '本月',
      start: thisMonthStart,
      end: endOfDay(DateTime(now.year, now.month + 1, 0)),
    ),
    (
      label: '上月',
      start: lastMonthStart,
      end: endOfDay(DateTime(now.year, now.month, 0)),
    ),
    (label: '近三月', start: _monthsAgo(today, 3), end: endOfDay(today)),
    (label: '近半年', start: _monthsAgo(today, 6), end: endOfDay(today)),
    (
      label: '今年',
      start: DateTime(now.year, 1, 1),
      end: endOfDay(DateTime(now.year, 12, 31)),
    ),
    (
      label: '去年',
      start: DateTime(now.year - 1, 1, 1),
      end: endOfDay(DateTime(now.year - 1, 12, 31)),
    ),
  ];
}

/// n 个月前同一天（月末溢出时取目标月最后一天）。
DateTime _monthsAgo(DateTime d, int n) {
  final target = DateTime(d.year, d.month - n, 1);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(target.year, target.month, d.day > lastDay ? lastDay : d.day);
}

/// 匹配起止日期命中的快捷范围名，未命中返回 null。
String? matchPresetName(DateTime start, DateTime end) {
  for (final p in datePresets(DateTime.now())) {
    if (_sameDate(start, p.start) && _sameDate(end, p.end)) return p.label;
  }
  return null;
}
