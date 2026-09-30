import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';

/// 单个标签（收入/支出）的宽度。
const double _kTabWidth = 72;

/// 文字区高度。
const double _kTextHeight = 36;

/// 滑块区高度，文字格与滑块同属一个点击容器，波纹贯通。
const double _kIndicatorHeight = 4;

class TabSwitcherAppBar extends AppBar {
  TabSwitcherAppBar({
    super.key,
    required List<String> tabs,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
    super.backgroundColor,
    super.leading,
    super.actions,
  }) : super(
         foregroundColor: colorTextOnPrimary,
         elevation: 0,
         centerTitle: true,
         toolbarHeight: _kTextHeight + _kIndicatorHeight,
         title: SizedBox(
           width: _kTabWidth * tabs.length,
           height: _kTextHeight + _kIndicatorHeight,
           child: Stack(
             children: [
               Row(
                 mainAxisSize: MainAxisSize.max,
                 children: List.generate(tabs.length, (i) {
                   final isSelected = selectedIndex == i;
                   return InkWell(
                     onTap: () => onChanged(i),
                     child: SizedBox(
                       width: _kTabWidth,
                       height: _kTextHeight + _kIndicatorHeight,
                       child: Padding(
                         padding: const EdgeInsets.only(
                           bottom: _kIndicatorHeight,
                         ),
                         child: Center(
                           child: Text(
                             tabs[i],
                             style: TextStyle(
                               fontSize: 18,
                               fontWeight: isSelected
                                   ? FontWeight.w600
                                   : FontWeight.w400,
                               color: colorTextOnPrimary,
                             ),
                           ),
                         ),
                       ),
                     ),
                   );
                 }),
               ),
               Positioned(
                 left: 0,
                 right: 0,
                 bottom: 0,
                 height: _kIndicatorHeight,
                 child: IgnorePointer(
                   child: Stack(
                     children: [
                       AnimatedPositioned(
                         duration: const Duration(milliseconds: 200),
                         left: _kTabWidth * selectedIndex,
                         top: 0,
                         child: Container(
                           width: _kTabWidth,
                           height: _kIndicatorHeight - 1,
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
             ],
           ),
         ),
       );
}
