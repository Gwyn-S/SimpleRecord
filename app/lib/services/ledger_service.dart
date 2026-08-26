import 'package:sqflite/sqflite.dart';

import '../models/ledger.dart';
import '../models/record.dart';
import '../utils/id.dart';
import 'database.dart';
import 'image_storage_service.dart';
import 'record_service.dart';

class LedgerStats {
  const LedgerStats({required this.count, required this.income, required this.expense});
  final int count;
  final int income;
  final int expense;
}

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

Future<List<Ledger>> loadLedgers() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query('books', orderBy: 'created_at');
  return rows.map(Ledger.fromDbMap).toList();
}

Future<void> insertLedger(Ledger ledger) async {
  final db = await DatabaseHelper.instance.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('books', {
    ...ledger.toDbMap(),
    'created_at': ledger.createdAt != 0 ? ledger.createdAt : now,
  },
      conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> updateLedger(Ledger ledger) async {
  final db = await DatabaseHelper.instance.database;
  await db.update('books', ledger.toDbMap(),
      where: 'id = ?', whereArgs: [ledger.id]);
}

Future<void> deleteLedger(String id) async {
  final db = await DatabaseHelper.instance.database;
  // 先查询该账本下所有记录的图片路径
  final rows = await db.query('records',
      columns: ['image_path'], where: 'book_id = ?', whereArgs: [id]);
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
  if (currentLedgerId.value == null || !ledgers.any((l) => l.id == currentLedgerId.value)) {
    await saveCurrentLedgerId(ledgers.first.id);
  }
  return currentLedgerId.value!;
}
