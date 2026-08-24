import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/category.dart';
import '../services/theme_service.dart';
import '../utils/formatters.dart';
import 'card_container.dart';

/// 排行榜数据项
class RankingItem {
  final String name;
  final int amountCents;
  final int count;
  final IconData? icon;

  const RankingItem({
    required this.name,
    required this.amountCents,
    this.count = 0,
    this.icon,
  });
}

/// 通用排行榜卡片
class StatsRankingCard extends StatelessWidget {
  final String title;
  final List<RankingItem> items;
  final Color? progressColor;

  const StatsRankingCard({
    super.key,
    required this.title,
    required this.items,
    this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return CardContainer(
        title: title,
        child: const SizedBox.shrink(),
      );
    }

    final total = items.fold(0, (s, e) => s + e.amountCents);
    final themeColor = progressColor ?? Theme.of(context).extension<AppThemeColors>()!.primary;

    return CardContainer(
      title: title,
      child: Column(
        children: items.asMap().entries.map((entry) {
          final item = entry.value;
          final ratio = total > 0 ? (item.amountCents / total).clamp(0.0, 1.0) : 0.0;
          final percent = (ratio * 100).toStringAsFixed(1);
          final category = expenseCategories.firstWhere(
            (c) => c.name == item.name,
            orElse: () => Category(icon: item.icon ?? Icons.category, name: item.name),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: sizeCategoryCircle,
                  height: sizeCategoryCircle,
                  decoration: const BoxDecoration(
                    color: colorIconLightBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    category.icon,
                    size: iconSizeXLarge,
                    color: colorIconGray,
                  ),
                ),
                const SizedBox(width: spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(item.name, style: textBody),
                          const SizedBox(width: spacingM),
                          Text('$percent%', style: textBody.copyWith(color: colorTextPrimary)),
                          const Spacer(),
                          if (item.count > 0) ...[
                            Text('(共${item.count}笔)', style: textItemSub.copyWith(color: colorTextHint)),
                            const SizedBox(width: spacingXS),
                          ],
                          Text(formatAmount(item.amountCents), style: textAmountFlow),
                        ],
                      ),
                      const SizedBox(height: spacingS),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: colorDivider,
                          valueColor: AlwaysStoppedAnimation(themeColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
