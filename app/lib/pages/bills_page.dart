import 'package:flutter/material.dart';
import '../theme.dart';
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

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta);
    });
  }

  String get _monthLabel =>
      '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) {
            return Container(
              color: color,
              child: Column(
                children: [
                  _buildTopBar(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _block('本月结余', '0.00', large: true)),
                            Expanded(child: _block('剩余预算', '0.00')),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: _block('本月收入', '0.00')),
                            Expanded(child: _block('本月支出', '0.00')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _block(String label, String amount, {bool large = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: large ? 16 : 14, fontWeight: FontWeight.w400, color: Colors.white)),
        const SizedBox(height: 6),
        Text('¥ $amount', style: TextStyle(fontSize: large ? 28 : 22, fontWeight: FontWeight.w400, letterSpacing: -1, color: Colors.white)),
      ],
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
