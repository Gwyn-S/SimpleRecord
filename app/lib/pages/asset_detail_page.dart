import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/asset_account.dart';
import '../services/theme_service.dart';
import '../services/asset_account_service.dart';
import '../utils/formatters.dart';
import 'asset_account_form_page.dart';
import 'asset_bill_page.dart';
import 'asset_trend_page.dart';

class AssetDetailPage extends StatefulWidget {
  final AssetAccount account;

  const AssetDetailPage({super.key, required this.account});

  @override
  State<AssetDetailPage> createState() => _AssetDetailPageState();
}

class _AssetDetailPageState extends State<AssetDetailPage> {
  AssetAccount get account => widget.account;

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      backgroundColor: colorBackgroundPage,
      appBar: AppBar(
        title: const Text('资产详情'),
        backgroundColor: themeColor,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssetTrendPage(account: account),
              ),
            ),
            child: const Text(
              '趋势图',
              style: TextStyle(color: colorTextOnPrimary, fontSize: 16),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssetBillPage(account: account),
              ),
            ),
            child: const Text(
              '账单',
              style: TextStyle(color: colorTextOnPrimary, fontSize: 16),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(spacingL),
              children: [_buildAccountCard(themeColor)],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: colorBackgroundCard,
              border: Border(top: BorderSide(color: colorDivider)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _buildAction(
                    context,
                    '转账',
                    Icons.swap_horiz,
                    colorTextPrimary,
                    () {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('转账（开发中）')));
                    },
                  ),
                  _buildActionDivider(),
                  _buildAction(
                    context,
                    '修改',
                    Icons.edit_outlined,
                    colorTextPrimary,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddAssetAccountFormPage(
                            title: '修改${account.categoryName}',
                            categoryName: account.categoryName,
                            nameLabel: _isCardAccount ? '所在银行' : '名称',
                            nameEditable: !_isCardAccount,
                            existingAccount: account,
                            presetName: account.name,
                            presetIconPath: account.iconPath,
                            showCardField: _isCardAccount,
                            emptyNameFallback: account.name,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildActionDivider(),
                  _buildAction(
                    context,
                    '删除',
                    Icons.delete_outline,
                    colorDelete,
                    () => _showDeleteDialog(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(Color themeColor) {
    final iconPath = account.iconPath.isNotEmpty
        ? account.iconPath
        : account.category?.iconPath ?? '';
    return Container(
      padding: const EdgeInsets.all(spacingL),
      decoration: BoxDecoration(
        color: colorBackgroundCard,
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                account.cardLast4.isNotEmpty
                    ? '${account.name}(${account.cardLast4})'
                    : account.name,
                style: textListItem.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: spacingXS),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  account.categoryName,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const Spacer(),
              iconPath.isNotEmpty
                  ? SvgPicture.asset(
                      iconPath,
                      width: iconSizeLarge,
                      height: iconSizeLarge,
                      fit: BoxFit.contain,
                    )
                  : Icon(
                      account.category?.icon ?? Icons.account_balance_wallet,
                      size: iconSizeLarge,
                      color: themeColor,
                    ),
            ],
          ),
          const SizedBox(height: spacingM),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatAmount(account.balanceCents),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: colorTextPrimary,
                      ),
                    ),
                    const SizedBox(height: spacingXXS),
                    const Text('余额', style: textItemSub),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => _showAdjustBalanceDialog(context),
                style: FilledButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: colorTextOnPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radiusMedium),
                  ),
                ),
                child: const Text('调整余额'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAdjustBalanceDialog(BuildContext context) {
    final controller = TextEditingController(
      text: formatAmount(account.balanceCents),
    );
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('调整余额'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final text = controller.text.trim();
              final cents = text.isEmpty || double.tryParse(text) == null
                  ? 0
                  : yuanToCents(text);
              account.balanceCents = cents;
              await updateAssetAccount(account);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildAction(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: spacingM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSizeDefault, color: color),
              const SizedBox(width: spacingXS),
              Text(label, style: textBody.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isCardAccount =>
      account.categoryName == '储蓄卡' || account.categoryName == '信用卡';

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确定删除「${account.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await deleteAssetAccount(account.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: colorDelete)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionDivider() {
    return Container(width: 1, color: colorDivider);
  }
}
