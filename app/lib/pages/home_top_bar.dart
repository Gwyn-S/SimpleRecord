import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
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
      height: heightHeaderBar,
      padding: const EdgeInsets.symmetric(horizontal: spacingL),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookListPage())),
            child: const Icon(Icons.book_outlined, size: iconSizeLarge, color: colorTextOnPrimary),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupPage())),
            child: const Icon(Icons.backup_outlined, size: iconSizeLarge, color: colorTextOnPrimary),
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
                    child: Icon(Icons.keyboard_arrow_left, size: iconSizeSmall, color: colorTextOnPrimary),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: spacingXXS),
                child: Text(
                  monthLabel,
                  style: textTitle,
                ),
              ),
              GestureDetector(
                onTap: onNextMonth,
                child: const SizedBox(
                  width: 36,
                  height: 40,
                  child: Align(
                    alignment: Alignment.center,
                    child: Icon(Icons.keyboard_arrow_right, size: iconSizeSmall, color: colorTextOnPrimary),
                  ),
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
            child: const Icon(Icons.search, size: iconSizeLarge, color: colorTextOnPrimary),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserPage())),
            child: const Icon(Icons.person_outline, size: iconSizeLarge, color: colorTextOnPrimary),
          ),
        ],
      ),
    );
  }
}
