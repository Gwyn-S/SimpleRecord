import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';

class HomeTopBar extends StatelessWidget {
  final String monthLabel;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback? onLedgerTap;
  final VoidCallback? onBackupTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onUserTap;

  const HomeTopBar({
    super.key,
    required this.monthLabel,
    required this.onPrevMonth,
    required this.onNextMonth,
    this.onLedgerTap,
    this.onBackupTap,
    this.onSearchTap,
    this.onUserTap,
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
            onTap: onLedgerTap,
            child: const Icon(Icons.book_outlined, size: iconSizeLarge, color: colorTextOnPrimary),
          ),
          GestureDetector(
            onTap: onBackupTap,
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
            onTap: onSearchTap,
            child: const Icon(Icons.search, size: iconSizeLarge, color: colorTextOnPrimary),
          ),
          GestureDetector(
            onTap: onUserTap,
            child: const Icon(Icons.person_outline, size: iconSizeLarge, color: colorTextOnPrimary),
          ),
        ],
      ),
    );
  }
}
