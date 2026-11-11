import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../models/data/ledger.dart';
import '../../models/data/ledger_stats.dart';
import '../../models/data/record.dart';
import '../../utils/formatters.dart';
import '../../utils/id.dart';
import '../core/author_service.dart';
import '../core/cloud_config.dart';
import '../core/database.dart';
import '../image/image_storage_service.dart';
import 'asset_account_service.dart' show assetAccountsVersion;
import 'balance_history_service.dart';
import 'record_service.dart';
import 'category_service.dart';
import '../cloud/supabase_service.dart';
import '../cloud/sync_service.dart';

/// 各账本记录数与收支合计，SQL 一次聚合，
/// 避免全表加载后在 Dart 内存里重复过滤统计。
Future<Map<String, LedgerStats>> loadLedgerStats() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.rawQuery('''
    SELECT book_id,
           COUNT(*) AS cnt,
           COALESCE(SUM(CASE WHEN is_expense = 0 THEN amount_cents END), 0) AS income,
           COALESCE(SUM(CASE WHEN is_expense = 1 THEN amount_cents END), 0) AS expense
    FROM records
    GROUP BY book_id
  ''');
  return {
    for (final r in rows)
      if (r['book_id'] is String)
        r['book_id'] as String: LedgerStats(
          count: r['cnt'] as int,
          income: (r['income'] as num).toInt(),
          expense: (r['expense'] as num).toInt(),
        ),
  };
}

/// 各账本按作者分组的结余（收入-支出），key 为作者 author_id（未发版，历史无此列处理可忽略）。
Future<Map<String, Map<String, int>>> loadLedgerPerAuthorBalance() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.rawQuery('''
    SELECT book_id,
           author_id AS author,
           SUM(CASE WHEN is_expense = 0 THEN amount_cents
                    WHEN is_expense = 1 THEN -amount_cents
                    ELSE 0 END) AS bal
    FROM records
    GROUP BY book_id, author_id
  ''');
  final result = <String, Map<String, int>>{};
  for (final r in rows) {
    final bookId = r['book_id'] as String?;
    if (bookId == null) continue;
    final author = (r['author'] as String?) ?? '';
    final bal = (r['bal'] as num).toInt();
    result.putIfAbsent(bookId, () => {})[author] = bal;
  }
  return result;
}

Future<List<Ledger>> loadLedgers() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query('books', orderBy: 'created_at ASC');
  final ledgers = rows.map(Ledger.fromDbMap).toList();
  // 换号归属过滤：本地账本(sync_mode=0)始终可见；共享账本只对
  // 归属(owner_author_id)匹配当前登录账号可见，其它账号/未登录隐藏。
  final authorId = await AuthorService.instance.existingAuthorId();
  final filtered = authorId != null
      ? ledgers
          .where(
            (l) =>
                l.syncMode != 1 ||
                l.ownerAuthorId == null ||
                l.ownerAuthorId == authorId,
          )
          .toList()
      : ledgers.where((l) => l.syncMode != 1).toList();
  // 稳定性排序：不区分本地/共享，统一按创建时间升序（旧的在前）。
  filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return filtered;
}

Future<void> insertLedger(Ledger ledger) async {
  final db = await DatabaseHelper.instance.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('books', {
    ...ledger.toDbMap(),
    'created_at': ledger.createdAt != 0 ? ledger.createdAt : now,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await seedCategoriesForLedger(ledger.id);
  SyncService.instance.enqueueLedger(ledger, op: 'insert');
}

Future<void> updateLedger(Ledger ledger) async {
  final db = await DatabaseHelper.instance.database;
  await db.update(
    'books',
    ledger.toDbMap(),
    where: 'id = ?',
    whereArgs: [ledger.id],
  );
  SyncService.instance.enqueueLedger(ledger, op: 'update');
  if (ledger.syncMode == 1) {
    // 共享账本改名：云端账本名同步更新（账本改名事件由 enqueueLedger 走 flush）。
    unawaited(SupabaseManager.instance.renameLedger(ledger.id, ledger.name));
  }
}

Future<void> deleteLedger(String id) async {
  final db = await DatabaseHelper.instance.database;
  bool wasShared = false;
  final bookRow = await db.query(
    'books',
    columns: ['sync_mode'],
    where: 'id = ?',
    whereArgs: [id],
  );
  if (bookRow.isNotEmpty) {
    wasShared = (bookRow.first['sync_mode'] as int) == 1;
  }
  if (wasShared) {
    // 共享账本：先推"账本已删"事件给对端（实时在线即时收到并清理本地），
    // 再删除云端房间行（ledger_ops 级联清理，成员资格一并失效）。
    // 任一步失败都不动本地，避免"本地删了云端还在"的矛盾状态。
    final supabase = SupabaseManager.instance;
    final ok = await supabase.appendLedgerOp(
      ledgerId: id,
      entityType: 'ledger',
      entityId: id,
      op: 'delete',
      payload: {
        'id': id,
        'name': '',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      deviceId: await getOrCreateDeviceId(),
    );
    if (ok == null) {
      throw Exception('账本删除事件推送失败');
    }
    final deleted = await supabase.deleteSharedLedger(id);
    if (!deleted) {
      throw Exception('云端账本删除失败');
    }
  }
  // 先查询该账本下所有记录：删除前把普通账户流水逐笔固化成调整行
  // （balance_adjustments）。删账本删的是"容器"不是"撤销消费"——花出去
  // 的钱不回退 balance_cents；但 records 真相删掉后曲线重放查不到那笔
  // 账，把每笔流水按同日期、同 delta 落成固化调整行（余额缓存不动），
  // 重算后曲线与余额继续一致。金库账户的调整行本就独立于 records 存在，
  // 余额/曲线天然一致，完全不动。顺带取出图片路径。
  final rows = await db.query('records', where: 'book_id = ?', whereArgs: [id]);
  for (final row in rows) {
    final imagePath = row['image_path'] as String?;
    if (imagePath != null && imagePath.isNotEmpty) {
      final paths = Record.imagePathsFromDb(imagePath);
      for (final path in paths) {
        await deleteImage(path);
      }
    }
  }
  final affectedAccounts = <String>{};
  final vaultChecked = <String, bool>{};
  await db.transaction((txn) async {
    for (final row in rows) {
      final record = Record.fromDbMap(row);
      final accountId = record.accountId;
      if (accountId == null || accountId.isEmpty) continue;
      var isVault = vaultChecked[accountId];
      if (isVault == null) {
        isVault = await isVaultAccountIdOn(txn, accountId);
        vaultChecked[accountId] = isVault;
      }
      if (isVault) continue;
      affectedAccounts.add(accountId);
      await BalanceHistoryService.instance.applyFlowRow(
        txn,
        accountId: accountId,
        sourceId: 'ledger-del:$id',
        recordKey: 'ledger-del-$id-rec-${record.id}',
        deltaCents: record.isExpense ? -record.amountCents : record.amountCents,
        date: toEpochDay(record.date),
        createdAt: record.createdAt.millisecondsSinceEpoch,
      );
    }
    await txn.delete('records', where: 'book_id = ?', whereArgs: [id]);
    await txn.delete('categories', where: 'ledger_id = ?', whereArgs: [id]);
    await txn.delete('budgets', where: 'ledger_id = ?', whereArgs: [id]);
    await txn.delete('books', where: 'id = ?', whereArgs: [id]);
  });
  recordsVersion.value++;
  assetAccountsVersion.value++;
  // 涉及账户的快照曲线异步重算（notifyChanged 内部有串行队列去重）。
  for (final accountId in affectedAccounts) {
    BalanceHistoryService.instance.notifyChanged(accountId);
  }
  await DatabaseHelper.instance.vacuum();
  if (wasShared) {
    unawaited(SyncService.instance.removeSharedState(id));
  }
}

/// 确保存在一个有效的当前账本：无账本时创建默认账本，
/// currentLedgerId 为空或已失效时选中第一个账本。
Future<String> ensureCurrentLedgerId() async {
  final ledgers = await loadLedgers();
  if (ledgers.isEmpty) {
    final ledger = Ledger(id: genId(), name: '日常');
    await insertLedger(ledger);
    await saveCurrentLedgerId(ledger.id);
    return ledger.id;
  }
  if (currentLedgerId.value == null ||
      !ledgers.any((l) => l.id == currentLedgerId.value)) {
    await saveCurrentLedgerId(ledgers.first.id);
  }
  return currentLedgerId.value!;
}
