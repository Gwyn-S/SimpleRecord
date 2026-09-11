import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/data/record.dart';
import '../../utils/formatters.dart';
import 'asset_account_service.dart';
import '../core/author_service.dart';
import 'balance_history_service.dart';
import '../core/database.dart';
import '../image/image_storage_service.dart';
import '../core/settings.dart';
import '../cloud/sync_service.dart';

const _currentLedgerKey = 'currentBookId';

final ValueNotifier<int> recordsVersion = ValueNotifier(0);
final ValueNotifier<String?> currentLedgerId = ValueNotifier(null);
final ValueNotifier<DateTime> currentMonth = ValueNotifier(
  DateTime(DateTime.now().year, DateTime.now().month),
);

Future<void> loadCurrentLedgerId() async {
  currentLedgerId.value = await Settings.getString(_currentLedgerKey);
}

Future<void> saveCurrentLedgerId(String? id) async {
  if (id == null) {
    await Settings.remove(_currentLedgerKey);
  } else {
    await Settings.setString(_currentLedgerKey, id);
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
    final start = toEpochDay(month);
    final end = toEpochDay(DateTime(month.year, month.month + 1));
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
  return AuthorService.instance.applyLatestNicknames(
    rows.map(Record.fromDbMap).toList(),
  );
}

/// 按日期范围查询记录（含 start，不含 end）
Future<List<Record>> loadRecordsByDateRange({
  String? ledgerId,
  required DateTime start,
  required DateTime end,
}) async {
  final db = await DatabaseHelper.instance.database;
  final where = <String>[];
  final args = <Object>[];
  if (ledgerId != null) {
    where.add('book_id = ?');
    args.add(ledgerId);
  }
  final startEpoch = toEpochDay(start);
  final endEpoch = toEpochDay(end);
  where.add('date >= ? AND date < ?');
  args.add(startEpoch);
  args.add(endEpoch);
  final sql = StringBuffer(
    'SELECT records.*, asset_accounts.name AS account_name '
    'FROM records LEFT JOIN asset_accounts '
    'ON records.account_id = asset_accounts.id',
  );
  sql.write(' WHERE ${where.join(' AND ')}');
  sql.write(' ORDER BY date DESC, created_at DESC');
  final rows = await db.rawQuery(sql.toString(), args);
  return AuthorService.instance.applyLatestNicknames(
    rows.map(Record.fromDbMap).toList(),
  );
}

/// 按日期范围查询并按分类聚合（支出）
Future<List<({String categoryName, int amountCents, int count})>>
loadExpenseByCategory({
  String? ledgerId,
  required DateTime start,
  required DateTime end,
}) async {
  final db = await DatabaseHelper.instance.database;
  final where = <String>['is_expense = 1'];
  final args = <Object>[];
  if (ledgerId != null) {
    where.add('book_id = ?');
    args.add(ledgerId);
  }
  final startEpoch = toEpochDay(start);
  final endEpoch = toEpochDay(end);
  where.add('date >= ? AND date < ?');
  args.add(startEpoch);
  args.add(endEpoch);
  final rows = await db.rawQuery(
    'SELECT category_name, SUM(amount_cents) AS total, COUNT(*) AS cnt '
    'FROM records '
    'WHERE ${where.join(' AND ')} '
    'GROUP BY category_name '
    'ORDER BY total DESC',
    args,
  );
  return rows
      .map(
        (r) => (
          categoryName: r['category_name'] as String,
          amountCents: r['total'] as int,
          count: r['cnt'] as int,
        ),
      )
      .toList();
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

/// 当前账本作者名：设置了昵称返回昵称，未设置返回 null（不打标签）。
/// 与 ownNickname() 读同一 Settings key，统一委托避免重复实现。
Future<String?> currentNickname() {
  return AuthorService.instance.ownNickname();
}

Future<void> insertRecord(Record record) async {
  final nickname = await currentNickname();
  final authorId = await AuthorService.instance.ensureAuthorId();
  record = record.copyWith(
    author: record.author ?? nickname,
    authorId: record.authorId ?? authorId,
  );
  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    await txn.insert(
      'records',
      record.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
  BalanceHistoryService.instance.notifyChanged(record.accountId);
  SyncService.instance.enqueueRecord(record, op: 'insert');
}

Future<void> updateRecord(Record record) async {
  final nickname = await currentNickname();
  final authorId = await AuthorService.instance.ensureAuthorId();
  record = record.copyWith(
    author: record.author ?? nickname,
    authorId: record.authorId ?? authorId,
  );
  final db = await DatabaseHelper.instance.database;
  String? oldAccountId;
  await db.transaction((txn) async {
    final rows = await txn.query(
      'records',
      where: 'id = ?',
      whereArgs: [record.id],
    );
    if (rows.isNotEmpty) {
      final old = Record.fromDbMap(rows.first);
      oldAccountId = old.accountId;
      await _applyBalance(
        txn,
        accountId: old.accountId,
        isExpense: old.isExpense,
        amountCents: old.amountCents,
        sign: -1,
      );
    }
    await txn.update(
      'records',
      record.toDbMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
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
  BalanceHistoryService.instance.notifyChanged(oldAccountId);
  BalanceHistoryService.instance.notifyChanged(record.accountId);
  SyncService.instance.enqueueRecord(record, op: 'update');
}

Future<void> deleteRecord(String id) async {
  final db = await DatabaseHelper.instance.database;
  Record? old;
  await db.transaction((txn) async {
    final rows = await txn.query('records', where: 'id = ?', whereArgs: [id]);
    await txn.delete('records', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final oldRecord = Record.fromDbMap(rows.first);
      old = oldRecord;
      await _applyBalance(
        txn,
        accountId: oldRecord.accountId,
        isExpense: oldRecord.isExpense,
        amountCents: oldRecord.amountCents,
        sign: -1,
      );
      // 删除关联的图片文件
      for (final path in oldRecord.imagePaths ?? []) {
        await deleteImage(path);
      }
    }
  });
  recordsVersion.value++;
  assetAccountsVersion.value++;
  BalanceHistoryService.instance.notifyChanged(old?.accountId);
  if (old != null) {
    await SyncService.instance.enqueueRecord(old!, op: 'delete');
  }
}
