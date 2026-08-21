import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';

class TabSwitcherAppBar extends AppBar {
  TabSwitcherAppBar({
    super.key,
    required List<String> tabs,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
    super.backgroundColor,
    super.leading,
  }) : super(
          foregroundColor: colorTextOnPrimary,
          elevation: 0,
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: SizedBox(
              width: 72.0 * tabs.length,
              height: 4,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    left: 72.0 * selectedIndex,
                    top: 0,
                    child: Container(
                      width: 72,
                      height: 3,
                      decoration: BoxDecoration(
                        color: colorTextOnPrimary,
                        borderRadius: BorderRadius.circular(radiusTiny),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(tabs.length, (i) {
              final isSelected = selectedIndex == i;
              return GestureDetector(
                onTap: () => onChanged(i),
                child: SizedBox(
                  width: 72,
                  height: 36,
                  child: Center(
                    child: Text(
                      tabs[i],
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: colorTextOnPrimary,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
}
