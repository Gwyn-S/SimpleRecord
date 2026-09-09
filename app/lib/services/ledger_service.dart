import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../models/ledger.dart';
import '../models/ledger_stats.dart';
import '../models/record.dart';
import '../utils/id.dart';
import 'author_service.dart';
import 'database.dart';
import 'image_storage_service.dart';
import 'record_service.dart';
import 'supabase_service.dart';
import 'sync_service.dart';

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
    // 共享账本改名：云端房间名同步更新（oplog 改名由 enqueueLedger 走 flush）。
    unawaited(SupabaseManager.instance.renameRoom(ledger.id, ledger.name));
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
  // 先查询该账本下所有记录的图片路径
  final rows = await db.query(
    'records',
    columns: ['image_path'],
    where: 'book_id = ?',
    whereArgs: [id],
  );
  for (final row in rows) {
    final imagePath = row['image_path'] as String?;
    if (imagePath != null && imagePath.isNotEmpty) {
      final paths = Record.imagePathsFromDb(imagePath);
      for (final path in paths) {
        await deleteImage(path);
      }
    }
  }
  await db.transaction((txn) async {
    await txn.delete('records', where: 'book_id = ?', whereArgs: [id]);
    await txn.delete('books', where: 'id = ?', whereArgs: [id]);
  });
  recordsVersion.value++;
  await DatabaseHelper.instance.vacuum();
  if (wasShared) {
    final ledger = Ledger(id: id, name: '');
    SyncService.instance.enqueueLedger(ledger, op: 'delete');
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
