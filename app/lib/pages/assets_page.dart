import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme.dart';
import '../models/asset_account.dart';
import '../widgets/summary_block.dart';
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

  double get _totalBalance => _accounts.fold(0.0, (s, a) => s + a.balance);

  String _fmt(double v) => v.toStringAsFixed(2);

  void _showEditDialog(int index) {
    final account = _accounts[index];
    final nameController = TextEditingController(text: account.name);
    final balanceController = TextEditingController(text: account.balance.toStringAsFixed(2));
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
              account.name = nameController.text.trim().isNotEmpty ? nameController.text.trim() : account.name;
              account.balance = double.tryParse(balanceController.text) ?? account.balance;
              await saveAssetAccounts(_accounts);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确定删除「${_accounts[index].name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              setState(() => _accounts.removeAt(index));
              await saveAssetAccounts(_accounts);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top),
        ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) {
            return Container(
              color: color,
              child: Column(
                children: [
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CustomPaint(
                            painter: _ChartAxisPainter(),
                            child: const Icon(Icons.show_chart, size: 16, color: Colors.white),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          '资产管理',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserPage())),
                          child: const Icon(Icons.person_outline, size: 22, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final halfW = constraints.maxWidth / 2;
                        return SizedBox(
                          height: 90,
                          child: Stack(
                            children: [
                              Positioned(left: 0, top: 0, width: halfW, height: 60, child: SummaryBlock('净资产', _fmt(_totalBalance), large: true)),
                              Positioned(left: 0, top: 60, width: halfW, child: SummaryBlock('资产', _fmt(_totalBalance))),
                              Positioned(left: halfW, top: 60, width: halfW, child: SummaryBlock('负债', '0.00')),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: _accounts.isEmpty
              ? const Center(
                  child: Text('点击 + 添加资产账户', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _accounts.length,
                  separatorBuilder: (_, _2) => Container(
                    height: 1,
                    color: const Color(0xFFEEEEEE),
                    margin: const EdgeInsets.only(left: 60),
                  ),
                  itemBuilder: (context, index) {
                    final account = _accounts[index];
                    return ValueListenableBuilder<Color>(
                      valueListenable: themeColorNotifier,
                      builder: (context, color, _) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: account.category?.iconPath != null
                                    ? SvgPicture.asset(
                                        account.category!.iconPath!,
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.contain,
                                        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                                      )
                                    : Icon(account.category?.icon ?? Icons.account_balance_wallet, size: 24, color: color),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(account.name, style: const TextStyle(fontSize: 15, color: Colors.black)),
                                    const SizedBox(height: 2),
                                    Text(account.categoryName, style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
                                  ],
                                ),
                              ),
                              Text(
                                _fmt(account.balance),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _showEditDialog(index),
                                child: Icon(Icons.edit, size: 24, color: color),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _showDeleteDialog(index),
                                child: const Icon(Icons.delete_outline, size: 24, color: Color(0xFF999999)),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

}

class _ChartAxisPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
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
