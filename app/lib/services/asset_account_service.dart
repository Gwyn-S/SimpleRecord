import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/asset_account.dart';
import 'database.dart';
import 'record_service.dart';

final ValueNotifier<int> assetAccountsVersion = ValueNotifier(0);

/// 具体类型 → 图标。icon_path 列新增前已有的账户按此回填。
const _iconByTypeName = {
  '微信': 'assets/icons/wechat.svg',
  '支付宝': 'assets/icons/alipay.svg',
  '工商银行': 'assets/icons/icbc.svg',
  '建设银行': 'assets/icons/ccb.svg',
  '农业银行': 'assets/icons/abc.svg',
  '中国银行': 'assets/icons/boc.svg',
  '招商银行': 'assets/icons/cmb.svg',
  '交通银行': 'assets/icons/comm_bank.svg',
  '中信银行': 'assets/icons/citic.svg',
  '浦发银行': 'assets/icons/spdb.svg',
  '广发银行': 'assets/icons/cgb.svg',
  '蚂蚁花呗': 'assets/icons/huabei.svg',
  '京东白条': 'assets/icons/jd_baitiao.svg',
  '股票': 'assets/icons/stocks.svg',
  '基金': 'assets/icons/funds.svg',
};

const _iconByCategory = {
  '现金': 'assets/icons/cash.svg',
  '网络账户': 'assets/icons/online_banking.svg',
  '储蓄卡': 'assets/icons/savings_card.svg',
  '信用卡': 'assets/icons/credit_card.svg',
  '投资': 'assets/icons/investment.svg',
  '负债': 'assets/icons/total_debt.svg',
  '债券': 'assets/icons/bonds.svg',
  '自定义资产': 'assets/icons/assets.svg',
};

/// 为 icon_path 为空的存量账户回填图标：
/// 优先按账户名匹配具体类型图标（微信/支付宝/银行等），否则回退到分类图标。
Future<void> backfillAccountIcons() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query('asset_accounts',
      where: 'icon_path = \'\'', columns: ['id', 'category_name', 'name']);
  for (final row in rows) {
    final icon = _iconByTypeName[row['name']] ?? _iconByCategory[row['category_name']];
    if (icon == null) continue;
    await db.update('asset_accounts', {'icon_path': icon},
        where: 'id = ?', whereArgs: [row['id']]);
  }
  if (rows.isNotEmpty) assetAccountsVersion.value++;
}

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
