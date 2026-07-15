import 'package:flutter/material.dart';
import 'calendar_lunar_utils.dart';

class CalendarCell extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final bool isSelected;
  final double expense;
  final double income;
  final LunarInfo lunar;
  final VoidCallback onTap;
  final Color themeColor;

  const CalendarCell({
    super.key,
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.expense,
    required this.income,
    required this.lunar,
    required this.onTap,
    required this.themeColor,
  });

  static String _fmtInt(double v) => v.round().toString();

  @override
  Widget build(BuildContext context) {
    final day = date.day;
    final solar = solarFest(date);
    final displayFestival = solar.isNotEmpty ? solar : (lunar.isFestival ? lunar.text : '');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isToday ? const Color(0xFFFFF8E1) : Colors.transparent,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: isSelected ? themeColor : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  const Expanded(child: SizedBox()),
                  Expanded(
                    child: Center(
                      child: Text(
                        '$day'.padLeft(2, '0'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: (displayFestival.isNotEmpty
                                    ? displayFestival
                                    : lunar.text)
                                .split('')
                                .map((c) => Text(
                                      c,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: displayFestival.isNotEmpty
                                            ? const Color(0xFFC62828)
                                            : const Color(0xFF666666),
                                      ),
                                    ))
                                .toList(),
                          ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: income > 0
                    ? Text(
                        '+${_fmtInt(income)}',
                        style: TextStyle(fontSize: 12, color: themeColor),
                        maxLines: 1,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            Expanded(
              child: Center(
                child: expense > 0
                    ? Text(
                        '-${_fmtInt(expense)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFE53935)),
                        maxLines: 1,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
