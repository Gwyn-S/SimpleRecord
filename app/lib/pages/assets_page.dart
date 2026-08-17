import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../models/asset_account.dart';
import '../services/asset_account_service.dart';
import '../utils/formatters.dart';
import '../widgets/account_avatar.dart';
import '../widgets/summary_block.dart';
import 'asset_detail_page.dart';
import 'asset_statistics_page.dart';
import 'user_page.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  List<AssetAccount> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    assetAccountsVersion.addListener(_loadAccounts);
  }

  @override
  void dispose() {
    assetAccountsVersion.removeListener(_loadAccounts);
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final accounts = await loadAssetAccounts();
    if (!mounted) return;
    setState(() => _accounts = accounts);
  }

  int get _totalAssets => _accounts
      .where((a) => !a.isDebtAccount)
      .fold(0, (s, a) => s + a.balanceCents);

  int get _totalDebt => _accounts
      .where((a) => a.isDebtAccount)
      .fold(0, (s, a) => s + a.balanceCents.abs());

  int get _netWorth => _totalAssets - _totalDebt;

  Map<String, List<AssetAccount>> get _grouped {
    final map = <String, List<AssetAccount>>{};
    for (final a in _accounts) {
      map.putIfAbsent(a.categoryName, () => []).add(a);
    }
    return map;
  }

  Color _categoryColor(String categoryName) {
    final cat = assetAccountCategories.where((c) => c.name == categoryName);
    return cat.isNotEmpty ? cat.first.color : colorAssetCustom;
  }

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
                        MaterialPageRoute(builder: (_) => const AssetStatisticsPage()),
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
          child: _accounts.isEmpty
              ? const Center(child: Text('点击 + 添加资产账户', style: textHint))
              : _buildCategoryList(),
        ),
      ],
    );
  }

  Widget _buildCategoryList() {
    final grouped = _grouped;
    return ListView.builder(
      padding: const EdgeInsets.all(spacingM),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final entry = grouped.entries.elementAt(index);
        final catName = entry.key;
        final accounts = entry.value;
        final color = _categoryColor(catName);
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
                    Text(formatAmount(total), style: textAccountAmount),
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
      },
    );
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
            AccountAvatar(account: account, size: iconSizeDefault, color: color),
            const SizedBox(width: spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.displayName,
                    style: textListItem,
                  ),
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
