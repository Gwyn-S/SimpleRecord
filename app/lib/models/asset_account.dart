import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'asset_accounts';

final ValueNotifier<int> assetAccountsVersion = ValueNotifier(0);

class AssetAccountCategory {
  final IconData? icon;
  final String? iconPath;
  final String name;

  const AssetAccountCategory({this.icon, this.iconPath, required this.name});
}

final assetAccountCategories = [
  const AssetAccountCategory(iconPath: 'assets/icons/cash.svg', name: '现金'),
  const AssetAccountCategory(iconPath: 'assets/icons/online_banking.svg', name: '网络支付'),
  const AssetAccountCategory(iconPath: 'assets/icons/savings_card.svg', name: '储蓄卡'),
  const AssetAccountCategory(iconPath: 'assets/icons/credit_card.svg', name: '信用卡'),
  const AssetAccountCategory(iconPath: 'assets/icons/investment.svg', name: '投资'),
  const AssetAccountCategory(iconPath: 'assets/icons/total_debt.svg', name: '负债'),
  const AssetAccountCategory(iconPath: 'assets/icons/bonds.svg', name: '债券'),
  const AssetAccountCategory(iconPath: 'assets/icons/assets.svg', name: '自定义资产'),
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

  AssetAccountCategory? get category {
    for (final c in assetAccountCategories) {
      if (c.name == categoryName) return c;
    }
    return null;
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
