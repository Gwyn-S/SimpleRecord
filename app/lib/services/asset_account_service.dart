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
  ...bankIconMap,
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

/// 资产汇总数据。
class AssetSummary {
  final int totalAssets;
  final int totalDebt;
  final int netWorth;
  final Map<String, List<AssetAccount>> grouped;

  const AssetSummary({
    required this.totalAssets,
    required this.totalDebt,
    required this.netWorth,
    required this.grouped,
  });
}

/// 从账户列表计算汇总数据。
AssetSummary computeSummary(List<AssetAccount> accounts) {
  var totalAssets = 0;
  var totalDebt = 0;
  for (final a in accounts) {
    if (a.isDebtAccount) {
      totalDebt += a.balanceCents.abs();
    } else {
      totalAssets += a.balanceCents;
    }
  }
  final grouped = <String, List<AssetAccount>>{};
  for (final a in accounts) {
    grouped.putIfAbsent(a.categoryName, () => []).add(a);
  }
  return AssetSummary(
    totalAssets: totalAssets,
    totalDebt: totalDebt,
    netWorth: totalAssets - totalDebt,
    grouped: grouped,
  );
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
