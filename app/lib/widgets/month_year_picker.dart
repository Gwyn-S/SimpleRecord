import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';

Future<DateTime?> showMonthYearPicker(BuildContext context, DateTime initial) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: colorBackgroundCard,
    builder: (ctx) => _MonthYearPickerSheet(initial: initial),
  );
}

/// 仅选择年份的picker
Future<DateTime?> showYearPicker(BuildContext context, DateTime initial, {int? maxYear}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: colorBackgroundCard,
    builder: (ctx) => _YearPickerSheet(initial: initial, maxYear: maxYear),
  );
}

class _YearPickerSheet extends StatefulWidget {
  const _YearPickerSheet({required this.initial, this.maxYear});

  final DateTime initial;
  final int? maxYear;

  @override
  State<_YearPickerSheet> createState() => _YearPickerSheetState();
}

class _YearPickerSheetState extends State<_YearPickerSheet> {
  static const int _minYear = 2000;
  late final int _maxYear;
  late int _year;
  late final FixedExtentScrollController _yearController;

  @override
  void initState() {
    super.initState();
    _maxYear = widget.maxYear ?? 2100;
    _year = widget.initial.year;
    _yearController =
        FixedExtentScrollController(initialItem: _year - _minYear);
  }

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.pop(context, DateTime(_year));
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).extension<AppThemeColors>()!.primary;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 200,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: spacingS),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(spacingM),
                      child: Text(
                        '取消',
                        style: TextStyle(fontSize: 16, color: colorTextSecondary),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _confirm,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(spacingM),
                      child: Text(
                        '确认',
                        style: TextStyle(fontSize: 16, color: primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: colorDivider),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: SizedBox(
                      width: 130,
                      height: double.infinity,
                      child: ListWheelScrollView(
                        controller: _yearController,
                        itemExtent: 38,
                        diameterRatio: 1.4,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (i) => setState(() => _year = _minYear + i),
                        children: List.generate(
                          _maxYear - _minYear + 1,
                          (i) => Center(child: Text('${_minYear + i} 年', style: textPickerItem)),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Container(
                      width: double.infinity,
                      height: 38,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: primary, width: 1),
                          bottom: BorderSide(color: primary, width: 1),
                        ),
                      ),
                    ),
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

class _MonthYearPickerSheet extends StatefulWidget {
  const _MonthYearPickerSheet({required this.initial});

  final DateTime initial;

  @override
  State<_MonthYearPickerSheet> createState() => _MonthYearPickerSheetState();
}

class _MonthYearPickerSheetState extends State<_MonthYearPickerSheet> {
  static const int _minYear = 2000;
  static const int _maxYear = 2100;

  late int _year;
  late int _month;
  late final FixedExtentScrollController _yearController;
  late final FixedExtentScrollController _monthController;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year;
    _month = widget.initial.month;
    _yearController =
        FixedExtentScrollController(initialItem: _year - _minYear);
    _monthController = FixedExtentScrollController(initialItem: _month - 1);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.pop(context, DateTime(_year, _month));
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).extension<AppThemeColors>()!.primary;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 200,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: spacingS),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(spacingM),
                      child: Text(
                        '取消',
                        style: TextStyle(fontSize: 16, color: colorTextSecondary),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _confirm,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(spacingM),
                      child: Text(
                        '确认',
                        style: TextStyle(fontSize: 16, color: primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: colorDivider),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildWheel(
                        width: 130,
                        controller: _yearController,
                        itemCount: _maxYear - _minYear + 1,
                        labelBuilder: (i) => '${_minYear + i} 年',
                        onChanged: (i) => setState(() => _year = _minYear + i),
                      ),
                      _buildWheel(
                        width: 110,
                        controller: _monthController,
                        itemCount: 12,
                        labelBuilder: (i) => '${i + 1} 月',
                        onChanged: (i) => setState(() => _month = i + 1),
                      ),
                    ],
                  ),
                  IgnorePointer(
                    child: Container(
                      width: double.infinity,
                      height: 38,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: primary, width: 1),
                          bottom: BorderSide(color: primary, width: 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWheel({
    required double width,
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int index) labelBuilder,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: width,
      height: double.infinity,
      child: ListWheelScrollView(
        controller: controller,
        itemExtent: 38,
        diameterRatio: 1.4,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        children: List.generate(
          itemCount,
          (i) => Center(child: Text(labelBuilder(i), style: textPickerItem)),
        ),
      ),
    );
  }
}
