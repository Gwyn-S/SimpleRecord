import 'package:flutter/material.dart';
import '../theme.dart';
import '../icon/app_icons.dart';
import '../models/record.dart';
import 'book_list_page.dart';
import 'backup_page.dart';
import 'search_page.dart';
import 'user_page.dart';

class BillsPage extends StatefulWidget {
  const BillsPage({super.key});

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<Record> _records = [];
  bool _loading = true;
  final Set<String> _expandedDays = {};
  bool _initialized = false;
  @override
  void initState() {
    super.initState();
    _loadRecords();
    recordsVersion.addListener(_loadRecords);
    currentBookId.addListener(_loadRecords);
  }

  @override
  void dispose() {
    recordsVersion.removeListener(_loadRecords);
    currentBookId.removeListener(_loadRecords);
    super.dispose();
  }

  Future<void> _loadRecords() async {
    final records = await loadRecords();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta);
      _expandedDays.clear();
      _initialized = false;
    });
  }

  String get _monthLabel =>
      '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}';

  List<Record> get _monthRecords {
    return _records.where((r) =>
        r.date.year == _currentMonth.year &&
        r.date.month == _currentMonth.month &&
        r.bookId == currentBookId.value).toList();
  }

  double get _monthIncome => _monthRecords
      .where((r) => !r.isExpense)
      .fold(0.0, (sum, r) => sum + r.amount);

  double get _monthExpense => _monthRecords
      .where((r) => r.isExpense)
      .fold(0.0, (sum, r) => sum + r.amount);

  double get _monthBalance => _monthIncome - _monthExpense;

  String _formatAmount(double v) => v.toStringAsFixed(2);

  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  String _formatDate(DateTime d) {
    return '${d.month}月${d.day}日 ${_weekdays[(d.weekday - 1) % 7]}';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView(
        children: [
          ValueListenableBuilder<Color>(
            valueListenable: themeColorNotifier,
            builder: (context, color, _) {
              return Container(
                color: color,
                child: Column(
                  children: [
                    SizedBox(height: MediaQuery.of(context).padding.top),
                    _buildTopBar(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final halfW = constraints.maxWidth / 2;
                          return SizedBox(
                            height: 90,
                            child: Stack(
                              children: [
                                Positioned(left: 0, top: 0, width: halfW, height: 60, child: _block('本月结余', _formatAmount(_monthBalance), large: true)),
                                Positioned(left: halfW, top: 30, width: halfW, child: _block('本月收入', _formatAmount(_monthIncome))),
                                Positioned(left: 0, top: 60, width: halfW, child: _block('剩余预算', null, emptyText: '点此设置')),
                                Positioned(left: halfW, top: 60, width: halfW, child: _block('本月支出', _formatAmount(_monthExpense))),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          _buildRecordList(),
        ],
      ),
    );
  }

  Widget _buildRecordList() {
    if (_loading) {
      return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    }
    final monthRecords = _monthRecords;
    if (monthRecords.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('暂无记录', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
        ),
      );
    }
    final grouped = <String, List<Record>>{};
    for (final r in monthRecords) {
      final key = '${r.date.year}-${r.date.month}-${r.date.day}';
      grouped.putIfAbsent(key, () => []).add(r);
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    if (sortedKeys.isNotEmpty && !_initialized) {
      _expandedDays.add(sortedKeys.first);
      _initialized = true;
    }

    return Column(
      children: sortedKeys.map((key) {
        final dayRecords = grouped[key]!;
        final date = dayRecords.first.date;
        final dayExpense = dayRecords.where((r) => r.isExpense).fold(0.0, (s, r) => s + r.amount);
        final dayIncome = dayRecords.where((r) => !r.isExpense).fold(0.0, (s, r) => s + r.amount);
        final expanded = _expandedDays.contains(key);
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  if (_expandedDays.contains(key)) {
                    _expandedDays.remove(key);
                  } else {
                    _expandedDays.add(key);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        _formatDate(date),
                        style: const TextStyle(fontSize: 14, color: Colors.black),
                      ),
                      const Spacer(),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                          children: [
                            const TextSpan(text: '收入 '),
                            TextSpan(text: _formatAmount(dayIncome), style: const TextStyle(color: Colors.black)),
                            const TextSpan(text: '  支出 '),
                            TextSpan(text: _formatAmount(dayExpense), style: const TextStyle(color: Colors.black)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: const Color(0xFF999999)),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
                ...dayRecords.map((r) => _buildRecordItem(r)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('结余：', style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
                      Text(
                        _formatAmount(dayIncome - dayExpense),
                        style: const TextStyle(fontSize: 14, color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecordItem(Record record) {
    IconData icon = Icons.help_outline;
    for (final c in [...expenseCategories, ...incomeCategories]) {
      if (c.name == record.categoryName) {
        icon = c.icon;
        break;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF333333)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.categoryName,
                  style: const TextStyle(fontSize: 15, color: Colors.black),
                ),
                if (record.remark.isNotEmpty)
                  Text(
                    record.remark,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                  ),
              ],
            ),
          ),
          Text(
            '${record.isExpense ? '-' : '+'}${_formatAmount(record.amount)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: record.isExpense ? Colors.black : const Color(0xFF4CAF50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _block(String label, String? amount, {bool large = false, String? emptyText}) {
    if (large) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
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
                Text(amount ?? '0.00', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w400, letterSpacing: -1, color: Colors.white)),
              ],
            ),
          ],
        ),
      );
    }
    if (emptyText != null && amount == null) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white)),
            const SizedBox(width: 4),
            Text(emptyText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white)),
          const SizedBox(width: 4),
          const Text('¥', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white)),
          const SizedBox(width: 2),
          Text(amount ?? '0.00', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400, letterSpacing: -1, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookListPage())),
            child: const Icon(Icons.book_outlined, size: 22, color: Colors.white),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupPage())),
            child: const Icon(Icons.backup_outlined, size: 22, color: Colors.white),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _changeMonth(-1),
                child: Icon(Icons.keyboard_arrow_left, size: 16, color: Colors.white),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  _monthLabel,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              GestureDetector(
                onTap: () => _changeMonth(1),
                child: Icon(Icons.keyboard_arrow_right, size: 16, color: Colors.white),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
            child: const Icon(Icons.search, size: 22, color: Colors.white),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserPage())),
            child: const Icon(Icons.person_outline, size: 22, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
