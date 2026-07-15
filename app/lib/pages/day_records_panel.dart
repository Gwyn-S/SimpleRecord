import 'package:flutter/material.dart';
import '../models/record.dart';
import '../widgets/record_item.dart';

class DayRecordsPanel extends StatelessWidget {
  final DateTime? selectedDay;
  final List<Record> records;
  final double dayIncome;
  final double dayExpense;
  final String Function(double) fmt;

  const DayRecordsPanel({
    super.key,
    required this.selectedDay,
    required this.records,
    required this.dayIncome,
    required this.dayExpense,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedDay == null) {
      return const Center(
        child: Text('点击日期查看当日记录', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
      );
    }

    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return Column(
      children: [
        Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      '${selectedDay!.month}月${selectedDay!.day}日 ${weekdays[(selectedDay!.weekday - 1) % 7]}',
                      style: const TextStyle(fontSize: 14, color: Colors.black),
                    ),
                    const Spacer(),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                        children: [
                          const TextSpan(text: '收入 '),
                          TextSpan(text: fmt(dayIncome), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black)),
                          const TextSpan(text: '  支出 '),
                          TextSpan(text: fmt(dayExpense), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.white,
            child: records.isEmpty
                ? const Center(
                    child: Text('当日无记录', style: TextStyle(fontSize: 14, color: Color(0xFFBBBBBB))),
                  )
                : ListView.builder(
                    itemCount: records.length,
                    itemBuilder: (context, index) => RecordItem(record: records[index], fmt: fmt),
                  ),
          ),
        ),
        Container(
          color: Colors.white,
          child: Column(
            children: [
              const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text('结余：', style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
                    Text(
                      fmt(dayIncome - dayExpense),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
