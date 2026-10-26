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

/// 刚记的那一天；账单页每次加载数据时消费它来自动展开该天（消费后置 null）。
final ValueNotifier<DateTime?> focusRecordDay = ValueNotifier(null);

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
  // account_name 直接读 records 自身的快照列，不再 JOIN asset_accounts：
  // 多人账本里"对方私有账户"的记录没有本地 id，靠同步过来的快照名显示。
  final rows = await db.query(
    'records',
    where: where.isEmpty ? null : where.join(' AND '),
    whereArgs: where.isEmpty ? null : args,
    orderBy: 'date DESC, created_at DESC',
  );
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
  // 与 loadRecords 同一快照列规则。
  final rows = await db.query(
    'records',
    where: where.join(' AND '),
    whereArgs: args,
    orderBy: 'date DESC, created_at DESC',
  );
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
/// 仅普通资产账户走这里；小金库走下面的行驱动路径（[_applyVaultFlow]）。
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

/// 小金库记账的行驱动路径：事务内把该记录的调整行置为目标态（[newDelta]，
/// null = 撤销），并把行 delta 变化量同步进 balance_cents；行已存在时只补
/// 差额（幂等，防补绑/重放二次扣减）。返回是否为金库路径，false 时调用方
/// 走普通账户 [_applyBalance]。
Future<bool> _applyVaultFlow(
  DatabaseExecutor txn, {
  required String? accountId,
  required String recordId,
  required int date,
  required int createdAt,
  required int? newDelta,
}) async {
  final id = accountId;
  if (id == null || id.isEmpty) return false;
  if (!await isVaultAccountId(id)) return false;
  final change = await BalanceHistoryService.instance.applyFlowRow(
    txn,
    accountId: id,
    recordKey: '$id-rec-$recordId',
    deltaCents: newDelta ?? 0,
    date: date,
    createdAt: createdAt,
    operatorEmail: SupabaseManager.instance.email ?? '',
  );
  if (change != 0) {
    await txn.rawUpdate(
      'UPDATE asset_accounts SET balance_cents = balance_cents + ? WHERE id = ?',
      [change, id],
    );
  }
  return true;
}

/// 当前账本作者名：设置了昵称返回昵称，未设置返回 null（不打标签）。
/// 与 ownNickname() 读同一 Settings key，统一委托避免重复实现。
Future<String?> currentNickname() {
  return AuthorService.instance.ownNickname();
}

/// 按账户 id 取账户名；无此账户返回 null。
Future<String?> _accountNameById(String accountId) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'asset_accounts',
    columns: ['name'],
    where: 'id = ?',
    whereArgs: [accountId],
  );
  return rows.isEmpty ? null : rows.first['name'] as String?;
}

/// 账户 id 是否指向共享金库（小金库分类 = 多人共享房间，两端同 id）。
Future<bool> isVaultAccountId(String accountId) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'asset_accounts',
    columns: ['category_name'],
    where: 'id = ?',
    whereArgs: [accountId],
  );
  return rows.isNotEmpty && rows.first['category_name'] == '小金库';
}

/// 给记录补账户名快照：account_name 随记录同步，是"两端都能看到账户"
/// 的唯一来源；创建入口（手动/AI）未带时按 accountId 回查一次兜底。
Future<Record> _withAccountSnapshot(Record record) async {
  if (record.accountName != null && record.accountName!.isNotEmpty) {
    return record;
  }
  final accId = record.accountId;
  if (accId == null || accId.isEmpty) return record;
  final name = await _accountNameById(accId);
  if (name == null || name.isEmpty) return record;
  return record.copyWith(accountName: name);
}

/// 当前登录账号对一条记录是否可写：
/// 绑共享金库的记录人人可写（两端同一本账，谁改都会同步对齐），
/// 其余记录仅作者本人可写；未登录或记录无作者归属时不拦（本地单人使用）。
Future<bool> canWriteRecord(Record record) async {
  final myId = await AuthorService.instance.existingAuthorId();
  if (myId == null || myId.isEmpty) return true;
  final authorId = record.authorId;
  if (authorId == null || authorId.isEmpty) return true;
  if (authorId == myId) return true;
  final accId = record.accountId;
  if (accId != null && accId.isNotEmpty && await isVaultAccountId(accId)) {
    return true;
  }
  return false;
}

Future<void> insertRecord(Record record) async {
  // 账户名快照兜底：手动/AI 创建入口未带时按 accountId 回查。
  record = await _withAccountSnapshot(record);
  final nickname = await currentNickname();
  final authorId = await AuthorService.instance.ensureAuthorId();
  record = record.copyWith(
    author: record.author ?? nickname,
    authorId: record.authorId ?? authorId,
  );
  final db = await DatabaseHelper.instance.database;
  final newDelta = record.isExpense ? -record.amountCents : record.amountCents;
  await db.transaction((txn) async {
    await txn.insert(
      'records',
      record.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // 金库走行驱动，普通账户直改。
    if (!await _applyVaultFlow(
      txn,
      accountId: record.accountId,
      recordId: record.id,
      date: toEpochDay(record.date),
      createdAt: record.createdAt.millisecondsSinceEpoch,
      newDelta: newDelta,
    )) {
      await _applyBalance(
        txn,
        accountId: record.accountId,
        isExpense: record.isExpense,
        amountCents: record.amountCents,
        sign: 1,
      );
    }
  });
  // 记一笔后：账单页会在下次加载数据时读取它并自动展开该天。
  focusRecordDay.value = DateTime(
    record.date.year,
    record.date.month,
    record.date.day,
  );
  recordsVersion.value++;
  assetAccountsVersion.value++;
  BalanceHistoryService.instance.notifyChanged(record.accountId);
  SyncService.instance.enqueueRecord(record, op: 'insert');
  // 金库作为资产账户的普通记账：只同步余额数值变化，不传流水明细。
  await _pushVaultDelta(record.accountId, record, op: 'insert');
}

/// 把金库记账的行目标态通告对端：insert/update 带 delta、delete 带撤销
/// 意图；本机调整行已由记账事务（[_applyVaultFlow]）落好，这里只通告。
/// [before]/[after] 仅作详情页展示字段，消费端不得用于余额赋值。
Future<void> _pushVaultDelta(
  String? accountId,
  Record record, {
  required String op,
}) async {
  if (accountId == null || accountId.isEmpty) return;
  // 仅金库账户需要：普通账户记账走本地完整流水，不生成数值事件。
  if (!await isVaultAccountId(accountId)) return;
  final recordKey = '$accountId-rec-${record.id}';
  final date = toEpochDay(record.date);
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  if (op == 'delete') {
    // 行已在记账事务内撤销，这里只广播撤销意图；对端删调整行，不碰 records 表。
    await VaultOpService.instance.pushRecordDeltaDelete(
      accountId: accountId,
      recordKey: recordKey,
      date: date,
      createdAt: nowMs,
    );
    return;
  }

  final delta = record.isExpense ? -record.amountCents : record.amountCents;
  // before/after 仅作展示：after = 发送端记账后的余额。
  final db = await DatabaseHelper.instance.database;
  final balRows = await db.query(
    'asset_accounts',
    columns: ['balance_cents'],
    where: 'id = ?',
    whereArgs: [accountId],
  );
  final after = balRows.isEmpty ? 0 : balRows.first['balance_cents'] as int;
  await VaultOpService.instance.pushRecordDelta(
    accountId: accountId,
    recordKey: recordKey,
    deltaCents: delta,
    beforeCents: after - delta,
    afterCents: after,
    date: date,
    createdAt: op == 'insert' ? record.createdAt.millisecondsSinceEpoch : nowMs,
  );
}

Future<bool> updateRecord(Record record) async {
  // 写权限兜底：他人记的私有/无账户记录只读（UI 已收口，此处防旁路）。
  if (!await canWriteRecord(record)) return false;
  // 账户名快照兜底：更新（含换账户）时同理。
  record = await _withAccountSnapshot(record);
  final nickname = await currentNickname();
  final authorId = await AuthorService.instance.ensureAuthorId();
  record = record.copyWith(
    author: record.author ?? nickname,
    authorId: record.authorId ?? authorId,
  );
  final db = await DatabaseHelper.instance.database;
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final newDelta = record.isExpense ? -record.amountCents : record.amountCents;
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
      if (oldAccountId != null) {
        if (oldAccountId != record.accountId) {
          // 换出/解绑：金库老流水行驱动撤销，对端只删调整行不删账；普通账户退旧值。
          if (!await _applyVaultFlow(
            txn,
            accountId: oldAccountId,
            recordId: old.id,
            date: toEpochDay(old.date),
            createdAt: nowMs,
            newDelta: null,
          )) {
            await _applyBalance(
              txn,
              accountId: old.accountId,
              isExpense: old.isExpense,
              amountCents: old.amountCents,
              sign: -1,
            );
          }
        } else if (!await isVaultAccountId(oldAccountId!)) {
          // 同普通账户改金额：退旧值与下方应用相抵；金库账户改金额不在此退，
          // 由下方行覆盖一次算出差额。
          await _applyBalance(
            txn,
            accountId: old.accountId,
            isExpense: old.isExpense,
            amountCents: old.amountCents,
            sign: -1,
          );
        }
      }
    }
    await txn.update(
      'records',
      record.toDbMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
    // 新账户应用：行覆盖的 delta 差额即缓存增量，补绑场景差额为 0。
    if (!await _applyVaultFlow(
      txn,
      accountId: record.accountId,
      recordId: record.id,
      date: toEpochDay(record.date),
      createdAt: nowMs,
      newDelta: newDelta,
    )) {
      await _applyBalance(
        txn,
        accountId: record.accountId,
        isExpense: record.isExpense,
        amountCents: record.amountCents,
        sign: 1,
      );
    }
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
  return true;
}

/// 删除一条记账。返回是否真的删到了 records 行（本地不存在则以 no-op
/// 处理，调用方可据此决定回退到调整行删除流程）。
Future<bool> deleteRecord(String id) async {
  final db = await DatabaseHelper.instance.database;
  // 写权限兜底：金库记录人人可删，其余仅作者本人；本地不存在时 no-op。
  final preRows = await db.query(
    'records',
    where: 'id = ?',
    whereArgs: [id],
  );
  if (preRows.isEmpty) return false;
  if (!await canWriteRecord(Record.fromDbMap(preRows.first))) return false;
  Record? old;
  await db.transaction((txn) async {
    final rows = await txn.query('records', where: 'id = ?', whereArgs: [id]);
    await txn.delete('records', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final oldRecord = Record.fromDbMap(rows.first);
      old = oldRecord;
      // 金库行驱动撤销（撤行 + 缓存回退同事务），普通账户直退。
      if (!await _applyVaultFlow(
        txn,
        accountId: oldRecord.accountId,
        recordId: oldRecord.id,
        date: toEpochDay(oldRecord.date),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        newDelta: null,
      )) {
        await _applyBalance(
          txn,
          accountId: oldRecord.accountId,
          isExpense: oldRecord.isExpense,
          amountCents: oldRecord.amountCents,
          sign: -1,
        );
      }
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
