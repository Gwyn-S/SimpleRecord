import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../models/asset_account.dart';
import '../services/asset_account_service.dart';
import '../utils/formatters.dart';
import '../widgets/summary_block.dart';
import 'user_page.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  static const _categoryColors = [
    colorAssetCash,
    colorAssetOnlinePay,
    colorAssetSavingsCard,
    colorAssetCreditCard,
    colorAssetInvestment,
    colorAssetDebt,
    colorAssetBond,
    colorAssetCustom,
  ];

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

  int get _totalAssets =>
      _accounts.where((a) => !a.isDebtAccount).fold(0, (s, a) => s + a.balanceCents);

  int get _totalDebt =>
      _accounts.where((a) => a.isDebtAccount).fold(0, (s, a) => s + a.balanceCents.abs());

  int get _netWorth => _totalAssets - _totalDebt;

  Map<String, List<AssetAccount>> get _grouped {
    final map = <String, List<AssetAccount>>{};
    for (final a in _accounts) {
      map.putIfAbsent(a.categoryName, () => []).add(a);
    }
    return map;
  }

  Color _categoryColor(String categoryName) {
    final idx = assetAccountCategories.indexWhere((c) => c.name == categoryName);
    return idx >= 0 ? _categoryColors[idx] : colorAssetCustom;
  }

  void _showEditDialog(AssetAccount account) {
    final nameController = TextEditingController(text: account.name);
    final balanceController = TextEditingController(text: formatAmount(account.balanceCents));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑账户'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: '账户名称', border: OutlineInputBorder()),
            ),
            const SizedBox(height: spacingM),
            TextField(
              controller: balanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: '余额', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              account.name = nameController.text.trim().isNotEmpty ? nameController.text.trim() : account.name;
              account.balanceCents = double.tryParse(balanceController.text) == null
                  ? account.balanceCents
                  : yuanToCents(balanceController.text);
              await updateAssetAccount(account);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(AssetAccount account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确定删除「${account.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await deleteAssetAccount(account.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: colorDelete)),
          ),
        ],
      ),
    );
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
                    SizedBox(
                      width: iconSizeLarge,
                      height: iconSizeLarge,
                      child: CustomPaint(
                        painter: _ChartAxisPainter(),
                        child: const Icon(Icons.show_chart, size: iconSizeSmall, color: colorTextOnPrimary),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '资产管理',
                      style: textTitle,
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserPage())),
                      child: const Icon(Icons.person_outline, size: iconSizeLarge, color: colorTextOnPrimary),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(spacingXXL, 0, spacingXXL, spacingXS),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final halfW = constraints.maxWidth / 2;
                    return SizedBox(
                      height: heightSummaryArea,
                      child: Stack(
                        children: [
                          Positioned(left: 0, top: 0, width: halfW, height: heightSummaryLarge, child: SummaryBlock('净资产', formatAmount(_netWorth), large: true)),
                          Positioned(left: 0, top: heightSummaryLarge, width: halfW, child: SummaryBlock('资产', formatAmount(_totalAssets))),
                          Positioned(left: halfW, top: heightSummaryLarge, width: halfW, child: SummaryBlock('负债', formatAmount(_totalDebt))),
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
              ? const Center(
                  child: Text('点击 + 添加资产账户', style: textHint),
                )
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
                padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingSM),
                child: Row(
                  children: [
                    Text(catName, style: textListItem),
                    const Spacer(),
                    Text(formatAmount(total), style: textAccountAmount),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: borderWidthThin, color: colorDivider),
              ...accounts.map((account) => _buildAccountRow(account, color)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountRow(AssetAccount account, Color color) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(spacingL, spacingSM, spacingL, spacingSM),
      child: Row(
        children: [
          Container(
            width: sizeIconContainer,
            height: sizeIconContainer,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: account.category?.iconPath != null
                ? SvgPicture.asset(
                    account.category!.iconPath!,
                    width: iconSizeDefault,
                    height: iconSizeDefault,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  )
                : Icon(account.category?.icon ?? Icons.account_balance_wallet, size: iconSizeDefault, color: color),
          ),
          const SizedBox(width: spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name, style: textListItem),
                if (account.cardLast4.isNotEmpty) ...[
                  const SizedBox(height: spacingXXS),
                  Text('尾号 ${account.cardLast4}', style: textItemSub),
                ],
                if (account.remark.isNotEmpty) ...[
                  const SizedBox(height: spacingXXS),
                  Text(account.remark, style: textItemSub),
                ],
              ],
            ),
          ),
          Text(
            formatAmount(account.balanceCents),
            style: textAccountAmount,
          ),
          const SizedBox(width: spacingS),
          GestureDetector(
            onTap: () => _showEditDialog(account),
            child: Icon(Icons.edit, size: iconSizeXLarge, color: themeColor),
          ),
          const SizedBox(width: spacingS),
          GestureDetector(
            onTap: () => _showDeleteDialog(account),
            child: const Icon(Icons.delete_outline, size: iconSizeXLarge, color: colorTextSecondary),
          ),
        ],
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

    canvas.drawLine(
      const Offset(2, 4),
      Offset(2, size.height - 2),
      paint,
    );
    canvas.drawLine(
      Offset(2, size.height - 2),
      Offset(size.width - 2, size.height - 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
