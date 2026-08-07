import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../theme.dart';
import '../models/asset_account.dart';
import '../services/asset_account_service.dart';
import '../utils/formatters.dart';
import '../utils/id.dart';

class AddAssetAccountPage extends StatefulWidget {
  const AddAssetAccountPage({super.key});

  @override
  State<AddAssetAccountPage> createState() => _AddAssetAccountPageState();
}

class _AddAssetAccountPageState extends State<AddAssetAccountPage> {
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

  void _showAddDialog(int index) {
    final cat = assetAccountCategories[index];
    final nameController = TextEditingController(text: cat.name);
    final balanceController = TextEditingController(text: '0');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加${cat.name}账户'),
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
              final name = nameController.text.trim().isNotEmpty ? nameController.text.trim() : cat.name;
              final balanceCents = double.tryParse(balanceController.text) == null
                  ? 0
                  : yuanToCents(balanceController.text);
              final account = AssetAccount(
                id: genId(),
                categoryName: cat.name,
                name: name,
                balanceCents: balanceCents,
              );
              await insertAssetAccount(account);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) => AppBar(
            backgroundColor: color,
            foregroundColor: colorTextOnPrimary,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '',
              onPressed: () => Navigator.pop(context),
            ),
            centerTitle: true,
            title: const Text('添加账户'),
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: spacingS),
        itemCount: assetAccountCategories.length,
        separatorBuilder: (_, _) => Container(
          height: 1,
          color: colorDivider,
          margin: const EdgeInsets.only(left: 72),
        ),
        itemBuilder: (context, index) {
          final cat = assetAccountCategories[index];
          final color = _categoryColors[index % _categoryColors.length];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showAddDialog(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: sizeIconContainer,
                    height: sizeIconContainer,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: cat.iconPath != null
                        ? SvgPicture.asset(
                            cat.iconPath!,
                            width: iconSizeXLarge,
                            height: iconSizeXLarge,
                            fit: BoxFit.contain,
                            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                          )
                        : Icon(cat.icon ?? Icons.account_balance_wallet, size: iconSizeXLarge, color: color),
                  ),
                  const SizedBox(width: spacingL),
                  Text(
                    cat.name,
                    style: const TextStyle(fontSize: 16, color: colorTextPrimary),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
