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
import '../cloud/supabase_service.dart';
import '../cloud/vault_op_service.dart';

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
  // 金库作为资产账户的普通记账：只同步余额数值变化，不传流水明细。
  await _pushVaultDelta(record.accountId, record, op: 'insert');
}

/// 记账影响了金库账户余额时，把数值变化（Δ）通告对端，
/// 并本地落一条「调整」历史，让详情页流水两端可见。
/// 普通账户不推；金库侧仅传 adjust 数值事件，保持"账户=数值"语义。
/// 一条记录的 insert/update/delete 共用稳定 recordKey（record.id 派生），
/// 因此本地调整行"一笔记账一行"：insert 新建、update 覆盖同值、delete 删除，
/// 不会像旧实现那样每次操作都追加一条反向记录。
Future<void> _pushVaultDelta(
  String? accountId,
  Record record, {
  required String op,
}) async {
  if (accountId == null || accountId.isEmpty) return;
  final db = await DatabaseHelper.instance.database;
  // 仅金库账户需要：普通账户记账走本地完整流水，不生成「调整」数值事件。
  final accRows = await db.query(
    'asset_accounts',
    columns: ['category_name'],
    where: 'id = ?',
    whereArgs: [accountId],
  );
  final isVault =
      accRows.isNotEmpty && accRows.first['category_name'] == '小金库';
  if (!isVault) return;
  // 后段读回终值余额作 after（insert/update 时记账事务已改好，
  // delete 时记账事务已回退）。
  final balRows = await db.query(
    'asset_accounts',
    columns: ['balance_cents'],
    where: 'id = ?',
    whereArgs: [accountId],
  );
  final after = balRows.isEmpty ? 0 : balRows.first['balance_cents'] as int;

  if (op == 'delete') {
    // 直接删除本记录对应的调整行（不做反向追加），事件只带 after 让对端删行。
    final recordKey = '$accountId-rec-${record.id}';
    await BalanceHistoryService.instance
        .removeAdjustmentByRecordKey(accountId, recordKey);
    await VaultOpService.instance.pushRecordDeltaDelete(
      accountId: accountId,
      recordKey: recordKey,
      afterCents: after,
      date: toEpochDay(record.date),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    return;
  }

  final newDelta = record.isExpense ? -record.amountCents : record.amountCents;
  // insert/update 均按"该记录当前对余额的影响"覆盖落行：
  // update = 整条替换（delta 记新影响），而非追加差值。
  final delta = newDelta;
  final before = after - delta;
  final recordKey = '$accountId-rec-${record.id}';
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  await BalanceHistoryService.instance.recordAdjustment(
    accountId: accountId,
    date: toEpochDay(record.date),
    deltaCents: delta,
    beforeCents: before,
    afterCents: after,
    createdAt: op == 'insert'
        ? record.createdAt.millisecondsSinceEpoch
        : nowMs,
    sourceId: '',
    operatorEmail: SupabaseManager.instance.email ?? '',
    recordKey: recordKey,
  );
  await VaultOpService.instance.pushRecordDelta(
    accountId: accountId,
    recordKey: recordKey,
    deltaCents: delta,
    beforeCents: before,
    afterCents: after,
    date: toEpochDay(record.date),
    createdAt: op == 'insert'
        ? record.createdAt.millisecondsSinceEpoch
        : nowMs,
  );
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
  // 更新可能改账户：新/旧账户有一个是金库就各推 Δ 变更。
  if (oldAccountId != null && oldAccountId != record.accountId) {
    await _pushVaultDelta(oldAccountId, record, op: 'delete');
  }
  await _pushVaultDelta(record.accountId, record, op: 'update');
}

/// 删除一条记账。返回是否真的删到了 records 行（本地不存在则以 no-op
/// 处理，调用方可据此决定回退到调整行删除流程）。
Future<bool> deleteRecord(String id) async {
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
    await _pushVaultDelta(old!.accountId, old!, op: 'delete');
  }
  return old != null;
}
