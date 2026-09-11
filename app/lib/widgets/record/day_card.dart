import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/record.dart';
import '../../utils/formatters.dart';

/// 每日记账卡片。bills / calendar / stats_detail 三处共用。
///
/// - [onToggle] 为 null 时不可折叠（恒展开、无箭头），如日历页。
/// - [margin] 为 null 时使用全宽无圆角样式（日历页）。
/// - [isShared] 为 true 时结余按作者分组显示（共享账本）。
class DayCard extends StatelessWidget {
  final List<Record> dayRecords;
  final bool expanded;
  final VoidCallback? onToggle;
  final bool isShared;
  final DateTime? headerDate;
  final Widget Function(BuildContext, Record) recordBuilder;
  final EdgeInsets? margin;

  const DayCard({
    super.key,
    required this.dayRecords,
    required this.expanded,
    this.onToggle,
    this.isShared = false,
    this.headerDate,
    required this.recordBuilder,
    this.margin,
  });

  bool get _collapsible => onToggle != null;

  int get _dayExp =>
      dayRecords.where((r) => r.isExpense).fold(0, (s, r) => s + r.amountCents);
  int get _dayInc => dayRecords
      .where((r) => !r.isExpense)
      .fold(0, (s, r) => s + r.amountCents);

  @override
  Widget build(BuildContext context) {
    final collapsible = _collapsible;
    final showBody = !collapsible || expanded;
    final date = headerDate ?? dayRecords.first.date;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: colorBackgroundCard,
        borderRadius: margin == null
            ? null
            : BorderRadius.circular(radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (collapsible)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: _buildHeader(date),
            )
          else
            _buildHeader(date),
          if (showBody) ...[
            const Divider(
              height: 1,
              thickness: borderWidthThin,
              color: colorDivider,
            ),
            ...dayRecords.map((r) => recordBuilder(context, r)),
            const Divider(
              height: 1,
              thickness: borderWidthThin,
              color: colorDivider,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: spacingL,
                vertical: spacingS,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('结余：', style: textSecondary),
                  if (isShared)
                    Text.rich(_sharedDayBalance())
                  else
                    Text(formatAmount(_dayInc - _dayExp), style: textBalance),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(DateTime date) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: 14),
      child: Row(
        children: [
          Text(formatDate(date), style: textBody),
          const Spacer(),
          Text.rich(
            TextSpan(
              style: textItemSub,
              children: [
                const TextSpan(text: '收入 '),
                TextSpan(text: formatAmount(_dayInc), style: textDayAmount),
                const TextSpan(text: '  支出 '),
                TextSpan(text: formatAmount(_dayExp), style: textDayAmount),
              ],
            ),
          ),
          if (_collapsible) ...[
            const SizedBox(width: spacingXS),
            Icon(
              expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
              size: iconSizeSmall,
              color: colorTextSecondary,
            ),
          ],
        ],
      ),
    );
  }

  /// 共享账本某日结余的数值部分：结余总计 + 按作者分组，如「-17.00 A：-8.00 B：-9.00」。
  TextSpan _sharedDayBalance() {
    final total = _dayInc - _dayExp;
    final map = <String, int>{};
    for (final r in dayRecords) {
      final name = r.author ?? '';
      map[name] =
          (map[name] ?? 0) + (r.isExpense ? -r.amountCents : r.amountCents);
    }
    final spans = <InlineSpan>[TextSpan(text: formatAmount(total))];
    map.forEach((name, bal) {
      spans
        ..add(
          TextSpan(
            text: ' $name',
            style: const TextStyle(
              fontWeight: FontWeight.w400,
              color: colorTextSecondary,
            ),
          ),
        )
        ..add(TextSpan(text: '：${formatAmount(bal)}'));
    });
    return TextSpan(style: textBalance, children: spans);
  }
}
