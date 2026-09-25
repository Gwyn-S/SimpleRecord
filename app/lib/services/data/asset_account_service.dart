import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/data/asset_account.dart';
import 'balance_history_service.dart';
import '../core/database.dart';
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

/// 为 icon_path 为空的存量账户回填图标：
/// 优先按账户名匹配具体类型图标（微信/支付宝/银行等），否则回退到分类图标。
Future<void> backfillAccountIcons() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'asset_accounts',
    where: 'icon_path = \'\'',
    columns: ['id', 'category_name', 'name'],
  );
  for (final row in rows) {
    final icon =
        _iconByTypeName[row['name']] ??
        assetAccountCategories
            .where((c) => c.name == row['category_name'])
            .map((c) => c.iconPath)
            .firstOrNull;
    if (icon == null) continue;
    await db.update(
      'asset_accounts',
      {'icon_path': icon},
      where: 'id = ?',
      whereArgs: [row['id']],
    );
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
  await db.insert(
    'asset_accounts',
    account.toDbMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  assetAccountsVersion.value++;
  BalanceHistoryService.instance.notifyChanged(account.id);
}

Future<void> updateAssetAccount(AssetAccount account, {String adjustSourceId = ''}) async {
  final db = await DatabaseHelper.instance.database;
  await db.update(
    'asset_accounts',
    account.toDbMap(),
    where: 'id = ?',
    whereArgs: [account.id],
  );
  // 手动改余额：使"今天"起的余额平移到新值，改动之前的历史不动。
  // 先落调整记录再通知监听，避免流水页面读到尚未写入的调整。
  // [adjustSourceId]：金库手动调整时与 pushAdjust 事件的 entityId 一致，
  // 靠 source_id 幂等，避免本机重放自己事件造成双写。
  await BalanceHistoryService.instance.applyManualAdjustment(
    account.id,
    sourceId: adjustSourceId,
  );
  assetAccountsVersion.value++;
}

Future<void> deleteAssetAccount(String id) async {
  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    await txn.delete('asset_accounts', where: 'id = ?', whereArgs: [id]);
    await txn.delete(
      'balance_snapshots',
      where: 'account_id = ?',
      whereArgs: [id],
    );
    await txn.delete(
      'balance_adjustments',
      where: 'account_id = ?',
      whereArgs: [id],
    );
    await txn.rawUpdate(
      'UPDATE records SET account_id = NULL WHERE account_id = ?',
      [id],
    );
  });
  assetAccountsVersion.value++;
  recordsVersion.value++;
}
