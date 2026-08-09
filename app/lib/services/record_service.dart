import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/record.dart';
import 'asset_account_service.dart';
import 'database.dart';

const _currentLedgerKey = 'currentBookId';

final ValueNotifier<int> recordsVersion = ValueNotifier(0);
final ValueNotifier<String?> currentLedgerId = ValueNotifier(null);
final ValueNotifier<DateTime> currentMonth = ValueNotifier(DateTime(DateTime.now().year, DateTime.now().month));

int _epochDayOf(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1970)).inDays;

Future<void> loadCurrentLedgerId() async {
  final prefs = await SharedPreferences.getInstance();
  currentLedgerId.value = prefs.getString(_currentLedgerKey);
}

Future<void> saveCurrentLedgerId(String? id) async {
  final prefs = await SharedPreferences.getInstance();
  if (id == null) {
    await prefs.remove(_currentLedgerKey);
  } else {
    await prefs.setString(_currentLedgerKey, id);
  }
  // 只置 currentLedgerId：ValueNotifier 值变化本身就会触发一次 reload，
  // 不再额外 ++recordsVersion，避免切账本时双触发两次全量加载。
  currentLedgerId.value = id;
}

Future<List<Record>> loadRecords({String? ledgerId, DateTime? month}) async {
  final db = await DatabaseHelper.instance.database;
  final where = <String>[];
  final args = <Object>[];
  if (ledgerId != null) {
    where.add('book_id = ?');
    args.add(ledgerId);
  }
  if (month != null) {
    final start = _epochDayOf(month);
    final end = _epochDayOf(DateTime(month.year, month.month + 1));
    where.add('date >= ? AND date < ?');
    args.add(start);
    args.add(end);
  }
  final sql = StringBuffer(
    'SELECT records.*, asset_accounts.name AS account_name '
    'FROM records LEFT JOIN asset_accounts '
    'ON records.account_id = asset_accounts.id',
  );
  if (where.isNotEmpty) {
    sql.write(' WHERE ${where.join(' AND ')}');
  }
  sql.write(' ORDER BY date DESC, created_at DESC');
  final rows = await db.rawQuery(sql.toString(), args);
  return rows.map(Record.fromDbMap).toList();
}

/// 同步账户余额：sign=1 应用记录影响，sign=-1 撤销。
/// 支出减余额、收入加余额；未关联账户（accountId 为空）时跳过。
Future<void> _applyBalance(
  DatabaseExecutor db, {
  required String? accountId,
  required bool isExpense,
  required int amountCents,
  required int sign,
}) async {
  if (accountId == null) return;
  final delta = sign * (isExpense ? -amountCents : amountCents);
  await db.rawUpdate(
    'UPDATE asset_accounts SET balance_cents = balance_cents + ? WHERE id = ?',
    [delta, accountId],
  );
}

Future<void> insertRecord(Record record) async {
  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    await txn.insert('records', record.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _applyBalance(
      txn,
      accountId: record.accountId,
      isExpense: record.isExpense,
      amountCents: record.amountCents,
      sign: 1,
    );
  });
  recordsVersion.value++;
  assetAccountsVersion.value++;
}

Future<void> updateRecord(Record record) async {
  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    final rows = await txn.query('records',
        where: 'id = ?', whereArgs: [record.id]);
    if (rows.isNotEmpty) {
      final old = Record.fromDbMap(rows.first);
      await _applyBalance(
        txn,
        accountId: old.accountId,
        isExpense: old.isExpense,
        amountCents: old.amountCents,
        sign: -1,
      );
    }
    await txn.update('records', record.toDbMap(),
        where: 'id = ?', whereArgs: [record.id]);
    await _applyBalance(
      txn,
      accountId: record.accountId,
      isExpense: record.isExpense,
      amountCents: record.amountCents,
      sign: 1,
    );
  });
  recordsVersion.value++;
  assetAccountsVersion.value++;
}

Future<void> deleteRecord(String id) async {
  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    final rows = await txn.query('records',
        where: 'id = ?', whereArgs: [id]);
    await txn.delete('records', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final old = Record.fromDbMap(rows.first);
      await _applyBalance(
        txn,
        accountId: old.accountId,
        isExpense: old.isExpense,
        amountCents: old.amountCents,
        sign: -1,
      );
    }
  });
  recordsVersion.value++;
  assetAccountsVersion.value++;
}
