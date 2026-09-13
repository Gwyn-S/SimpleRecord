import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../services/core/theme_service.dart';
import '../../models/data/asset_account.dart';
import '../../services/data/asset_account_service.dart';
import '../../services/data/piggy_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/account_avatar.dart';
import '../../widgets/chart/summary_block.dart';
import 'asset_detail_page.dart';
import 'asset_statistics_page.dart';
import '../record/user_page.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  List<AssetAccount> _accounts = [];
  List<MapEntry<String, List<AssetAccount>>> _categoryEntries = [];
  int _piggyPositiveTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _loadPiggies();
    assetAccountsVersion.addListener(_loadAccounts);
    PiggyService.instance.piggyVersion.addListener(_loadPiggies);
  }

  @override
  void dispose() {
    assetAccountsVersion.removeListener(_loadAccounts);
    PiggyService.instance.piggyVersion.removeListener(_loadPiggies);
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final accounts = await loadAssetAccounts();
    if (!mounted) return;
    final map = <String, List<AssetAccount>>{};
    for (final a in accounts) {
      map.putIfAbsent(a.categoryName, () => []).add(a);
    }
    setState(() {
      _accounts = accounts;
      _categoryEntries = map.entries.toList();
    });
  }

  /// 共同小金库余额合计（正余额计入净资产），随 piggyVersion 刷新。
  Future<void> _loadPiggies() async {
    final piggies = await PiggyService.instance.loadMyPiggies();
    var total = 0;
    for (final p in piggies) {
      final b = await PiggyService.instance.balanceOf(p.id);
      if (b > 0) total += b;
    }
    if (!mounted) return;
    setState(() {
      _piggyPositiveTotal = total;
    });
  }

  int get _totalAssets =>
      _accounts.where((a) => !a.isDebtAccount).fold(0, (s, a) => s + a.balanceCents) +
      _piggyPositiveTotal;

  int get _totalDebt => _accounts
      .where((a) => a.isDebtAccount)
      .fold(0, (s, a) => s + a.balanceCents.abs());

  int get _netWorth => _totalAssets - _totalDebt;

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Column(
      children: [
        Container(
          color: themeColor,
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top),
              Container(
                height: heightHeaderBar,
                padding: const EdgeInsets.symmetric(horizontal: spacingL),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AssetStatisticsPage(),
                        ),
                      ),
                      child: SizedBox(
                        width: iconSizeLarge,
                        height: iconSizeLarge,
                        child: CustomPaint(
                          painter: _ChartAxisPainter(),
                          child: const Icon(
                            Icons.show_chart,
                            size: iconSizeSmall,
                            color: colorTextOnPrimary,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text('资产管理', style: textTitle),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const UserPage()),
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        size: iconSizeLarge,
                        color: colorTextOnPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  spacingXXL,
                  0,
                  spacingXXL,
                  spacingXS,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final halfW = constraints.maxWidth / 2;
                    return SizedBox(
                      height: heightSummaryArea,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            width: halfW,
                            height: heightSummaryLarge,
                            child: SummaryBlock(
                              '净资产',
                              formatAmount(_netWorth),
                              large: true,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: heightSummaryLarge,
                            width: halfW,
                            child: SummaryBlock(
                              '资产',
                              formatAmount(_totalAssets),
                            ),
                          ),
                          Positioned(
                            left: halfW,
                            top: heightSummaryLarge,
                            width: halfW,
                            child: SummaryBlock('负债', formatAmount(_totalDebt)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(spacingM),
            children: [
              ..._buildCategorySections(),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCategorySections() {
    final grouped = _categoryEntries;
    return grouped.map((entry) {
      final catName = entry.key;
      final accounts = entry.value;
      final color = categoryColorByName(catName);
      final total = accounts.fold(0, (s, a) => s + a.balanceCents);
      return Container(
        margin: const EdgeInsets.only(bottom: spacingM),
        decoration: BoxDecoration(
          color: colorBackgroundCard,
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: spacingL,
                vertical: spacingSM,
              ),
              child: Row(
                children: [
                  Text(catName, style: textListItem),
                  const Spacer(),
                  Text(
                    formatAmountEdit(total),
                    style: textAccountAmount.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              thickness: borderWidthThin,
              color: colorDivider,
            ),
            ...accounts.map((account) => _buildAccountRow(account, color)),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildAccountRow(AssetAccount account, Color color) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AssetDetailPage(account: account)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          spacingL,
          spacingSM,
          spacingL,
          spacingSM,
        ),
        child: Row(
          children: [
            AccountAvatar(
              account: account,
              size: iconSizeDefault,
              color: color,
            ),
            const SizedBox(width: spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.displayName, style: textListItem),
                  if (account.remark.isNotEmpty) ...[
                    const SizedBox(height: spacingXXS),
                    Text(account.remark, style: textItemSub),
                  ],
                ],
              ),
            ),
            Text(formatAmount(account.balanceCents), style: textAccountAmount),
          ],
        ),
      ),
    );
  }
}

class _ChartAxisPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colorTextOnPrimary
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(const Offset(2, 4), Offset(2, size.height - 2), paint);
    canvas.drawLine(
      Offset(2, size.height - 2),
      Offset(size.width - 2, size.height - 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
