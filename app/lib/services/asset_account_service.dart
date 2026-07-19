import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/asset_account.dart';
import 'package:flutter/material.dart';

final ValueNotifier<int> assetAccountsVersion = ValueNotifier(0);

Future<List<AssetAccount>> loadAssetAccounts() async {
  final prefs = await SharedPreferences.getInstance();
  final str = prefs.getString('asset_accounts');
  if (str == null) return [];
  final list = jsonDecode(str) as List;
  return list.map((e) => AssetAccount.fromJson(e as Map<String, dynamic>)).toList();
}

Future<void> saveAssetAccounts(List<AssetAccount> accounts) async {
  final prefs = await SharedPreferences.getInstance();
  final str = jsonEncode(accounts.map((a) => a.toJson()).toList());
  await prefs.setString('asset_accounts', str);
  assetAccountsVersion.value++;
}
