import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/asset_account.dart';
import 'database.dart';
import 'record_service.dart';

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
  await db.transaction((txn) async {
    await txn.delete('asset_accounts', where: 'id = ?', whereArgs: [id]);
    await txn.rawUpdate(
        'UPDATE records SET account_id = NULL WHERE account_id = ?', [id]);
  });
  assetAccountsVersion.value++;
  recordsVersion.value++;
}
