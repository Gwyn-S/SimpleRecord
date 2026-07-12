import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'asset_accounts';

final ValueNotifier<int> assetAccountsVersion = ValueNotifier(0);

class AssetAccountCategory {
  final IconData icon;
  final String name;

  const AssetAccountCategory({required this.icon, required this.name});
}

final assetAccountCategories = [
  AssetAccountCategory(icon: Icons.payments, name: '现金'),
  AssetAccountCategory(icon: Icons.account_balance, name: '储蓄卡'),
  AssetAccountCategory(icon: Icons.credit_card, name: '信用卡'),
  AssetAccountCategory(icon: Icons.account_balance_wallet, name: '支付宝'),
  AssetAccountCategory(icon: Icons.chat_bubble, name: '微信'),
  AssetAccountCategory(icon: Icons.candlestick_chart, name: '股票'),
  AssetAccountCategory(icon: Icons.pie_chart, name: '基金'),
  AssetAccountCategory(icon: Icons.currency_bitcoin, name: '虚拟货币'),
  AssetAccountCategory(icon: Icons.more_horiz, name: '其他'),
];

class AssetAccount {
  final String id;
  String categoryName;
  String name;
  double balance;

  AssetAccount({
    required this.id,
    required this.categoryName,
    required this.name,
    this.balance = 0,
  });

  IconData get icon {
    for (final c in assetAccountCategories) {
      if (c.name == categoryName) return c.icon;
    }
    return Icons.account_balance_wallet;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryName': categoryName,
    'name': name,
    'balance': balance,
  };

  factory AssetAccount.fromJson(Map<String, dynamic> json) => AssetAccount(
    id: json['id'] as String,
    categoryName: json['categoryName'] as String,
    name: json['name'] as String,
    balance: (json['balance'] as num?)?.toDouble() ?? 0,
  );
}

Future<List<AssetAccount>> loadAssetAccounts() async {
  final prefs = await SharedPreferences.getInstance();
  final str = prefs.getString(_storageKey);
  if (str == null) return [];
  final list = jsonDecode(str) as List;
  return list.map((e) => AssetAccount.fromJson(e as Map<String, dynamic>)).toList();
}

Future<void> saveAssetAccounts(List<AssetAccount> accounts) async {
  final prefs = await SharedPreferences.getInstance();
  final str = jsonEncode(accounts.map((a) => a.toJson()).toList());
  await prefs.setString(_storageKey, str);
  assetAccountsVersion.value++;
}
