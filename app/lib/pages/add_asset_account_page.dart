import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme.dart';
import '../models/asset_account.dart';

class AddAssetAccountPage extends StatefulWidget {
  const AddAssetAccountPage({super.key});

  @override
  State<AddAssetAccountPage> createState() => _AddAssetAccountPageState();
}

class _AddAssetAccountPageState extends State<AddAssetAccountPage> {
  final _categoryColors = const [
    Color(0xFFE53935), // 现金
    Color(0xFF1E88E5), // 网络支付
    Color(0xFF43A047), // 储蓄卡
    Color(0xFFFDD835), // 信用卡
    Color(0xFFFB8C00), // 投资
    Color(0xFF8E24AA), // 负债
    Color(0xFF66BB6A), // 债券
    Color(0xFF546E7A), // 自定义资产
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
            const SizedBox(height: 12),
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
              final balance = double.tryParse(balanceController.text) ?? 0;
              final account = AssetAccount(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                categoryName: cat.name,
                name: name,
                balance: balance,
              );
              final accounts = await loadAssetAccounts();
              accounts.add(account);
              await saveAssetAccounts(accounts);
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
            foregroundColor: Colors.white,
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: assetAccountCategories.length,
        separatorBuilder: (_, _2) => Container(
          height: 1,
          color: const Color(0xFFF0F0F0),
          margin: const EdgeInsets.only(left: 72),
        ),
        itemBuilder: (context, index) {
          final cat = assetAccountCategories[index];
          final color = _categoryColors[index % _categoryColors.length];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showAddDialog(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: cat.iconPath != null
                        ? SvgPicture.asset(
                            cat.iconPath!,
                            width: 24,
                            height: 24,
                            fit: BoxFit.contain,
                            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                          )
                        : Icon(cat.icon ?? Icons.account_balance_wallet, size: 24, color: color),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    cat.name,
                    style: const TextStyle(fontSize: 16, color: Colors.black),
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
