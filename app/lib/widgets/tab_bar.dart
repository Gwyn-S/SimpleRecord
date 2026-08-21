import 'package:flutter/material.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';

class FilterTabBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const FilterTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Row(
      children: List.generate(tabs.length, (i) {
        final isSelected = selectedIndex == i;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              if (selectedIndex == i) return;
              onChanged(i);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: spacingM),
              color: isSelected ? themeColor : Colors.transparent,
              child: Text(
                tabs[i],
                textAlign: TextAlign.center,
                style: isSelected ? textFilterActive : textFilterInactive,
              ),
            ),
          ),
        );
      }),
    );
  }
}
