import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/asset_account.dart';
import 'database.dart';

final ValueNotifier<int> assetAccountsVersion = ValueNotifier(0);

Future<List<AssetAccount>> loadAssetAccounts() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query('asset_accounts', orderBy: 'category_name, name');
  return rows.map(AssetAccount.fromDbMap).toList();
}

Future<void> insertAssetAccount(AssetAccount account) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('asset_accounts', account.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace);
  assetAccountsVersion.value++;
}

Future<void> updateAssetAccount(AssetAccount account) async {
  final db = await DatabaseHelper.instance.database;
  await db.update('asset_accounts', account.toDbMap(),
      where: 'id = ?', whereArgs: [account.id]);
  assetAccountsVersion.value++;
}

Future<void> deleteAssetAccount(String id) async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('asset_accounts', where: 'id = ?', whereArgs: [id]);
  assetAccountsVersion.value++;
}
