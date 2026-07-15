import 'package:flutter/material.dart';
import 'book_list_page.dart';
import 'backup_page.dart';
import 'search_page.dart';
import 'user_page.dart';

class HomeTopBar extends StatelessWidget {
  final String monthLabel;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const HomeTopBar({
    super.key,
    required this.monthLabel,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
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
                onTap: onPrevMonth,
                child: const SizedBox(
                  width: 36,
                  height: 40,
                  child: Align(
                    alignment: Alignment.center,
                    child: Icon(Icons.keyboard_arrow_left, size: 16, color: Colors.white),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  monthLabel,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              GestureDetector(
                onTap: onNextMonth,
                child: const SizedBox(
                  width: 36,
                  height: 40,
                  child: Align(
                    alignment: Alignment.center,
                    child: Icon(Icons.keyboard_arrow_right, size: 16, color: Colors.white),
                  ),
                ),
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
