import 'package:sqflite/sqflite.dart';

import '../models/ledger.dart';
import '../models/record.dart';
import '../utils/id.dart';
import 'database.dart';
import 'record_service.dart';

int ledgerRecordCount(List<Record> records, String ledgerId) =>
    records.where((r) => r.ledgerId == ledgerId).length;

int ledgerIncome(List<Record> records, String ledgerId) =>
    records.where((r) => r.ledgerId == ledgerId && !r.isExpense).fold(0, (s, r) => s + r.amountCents);

int ledgerExpense(List<Record> records, String ledgerId) =>
    records.where((r) => r.ledgerId == ledgerId && r.isExpense).fold(0, (s, r) => s + r.amountCents);

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
  await db.transaction((txn) async {
    await txn.delete('records', where: 'book_id = ?', whereArgs: [id]);
    await txn.delete('books', where: 'id = ?', whereArgs: [id]);
  });
  recordsVersion.value++;
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
