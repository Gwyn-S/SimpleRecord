import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/transfer.dart';
import '../utils/formatters.dart';
import 'asset_account_service.dart';
import 'balance_history_service.dart';
import 'database.dart';
import '../utils/id.dart';

final ValueNotifier<int> transfersVersion = ValueNotifier(0);

Future<List<Transfer>> loadTransfersForAccount(String accountId) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.rawQuery(
    'SELECT t.*, a.name AS from_account_name, b.name AS to_account_name '
    'FROM transfers t '
    'LEFT JOIN asset_accounts a ON t.from_account_id = a.id '
    'LEFT JOIN asset_accounts b ON t.to_account_id = b.id '
    'WHERE t.from_account_id = ? OR t.to_account_id = ? '
    'ORDER BY t.date DESC, t.created_at DESC',
    [accountId, accountId],
  );
  return rows.map(Transfer.fromDbMap).toList();
}

/// 转账：事务内更新两个账户余额并写入流水。
/// 转出账户扣除 转账金额 + 手续费，转入账户增加转账金额。
Future<void> insertTransfer({
  required String fromAccountId,
  required String toAccountId,
  required int amountCents,
  int feeCents = 0,
  String remark = '',
  DateTime? date,
}) async {
  final db = await DatabaseHelper.instance.database;
  final now = DateTime.now();
  await db.transaction((txn) async {
    await txn.insert('transfers', {
      'id': genId(),
      'from_account_id': fromAccountId,
      'to_account_id': toAccountId,
      'amount_cents': amountCents,
      'fee_cents': feeCents,
      'remark': remark,
      'date': toEpochDay(date ?? now),
      'created_at': now.millisecondsSinceEpoch,
    });
    await _applyTransfer(
      txn,
      fromAccountId,
      toAccountId,
      amountCents,
      feeCents,
      1,
    );
  });
  transfersVersion.value++;
  assetAccountsVersion.value++;
  BalanceHistoryService.instance.notifyChanged(fromAccountId);
  BalanceHistoryService.instance.notifyChanged(toAccountId);
}

Future<void> _applyTransfer(
  DatabaseExecutor txn,
  String fromAccountId,
  String toAccountId,
  int amountCents,
  int feeCents,
  int sign,
) async {
  await txn.rawUpdate(
    'UPDATE asset_accounts SET balance_cents = balance_cents - ? WHERE id = ?',
    [sign * (amountCents + feeCents), fromAccountId],
  );
  await txn.rawUpdate(
    'UPDATE asset_accounts SET balance_cents = balance_cents + ? WHERE id = ?',
    [sign * amountCents, toAccountId],
  );
}

Future<void> updateTransfer(Transfer transfer) async {
  final db = await DatabaseHelper.instance.database;
  String? oldFrom;
  String? oldTo;
  await db.transaction((txn) async {
    final rows = await txn.query(
      'transfers',
      where: 'id = ?',
      whereArgs: [transfer.id],
    );
    if (rows.isNotEmpty) {
      final old = Transfer.fromDbMap(rows.first);
      oldFrom = old.fromAccountId;
      oldTo = old.toAccountId;
      await _applyTransfer(
        txn,
        old.fromAccountId,
        old.toAccountId,
        old.amountCents,
        old.feeCents,
        -1,
      );
    }
    await txn.update(
      'transfers',
      transfer.toDbMap(),
      where: 'id = ?',
      whereArgs: [transfer.id],
    );
    await _applyTransfer(
      txn,
      transfer.fromAccountId,
      transfer.toAccountId,
      transfer.amountCents,
      transfer.feeCents,
      1,
    );
  });
  transfersVersion.value++;
  assetAccountsVersion.value++;
  BalanceHistoryService.instance.notifyChanged(oldFrom);
  BalanceHistoryService.instance.notifyChanged(oldTo);
  BalanceHistoryService.instance.notifyChanged(transfer.fromAccountId);
  BalanceHistoryService.instance.notifyChanged(transfer.toAccountId);
}

Future<void> deleteTransfer(String id) async {
  final db = await DatabaseHelper.instance.database;
  String? fromId;
  String? toId;
  await db.transaction((txn) async {
    final rows = await txn.query('transfers', where: 'id = ?', whereArgs: [id]);
    await txn.delete('transfers', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final t = Transfer.fromDbMap(rows.first);
      fromId = t.fromAccountId;
      toId = t.toAccountId;
      await _applyTransfer(
        txn,
        t.fromAccountId,
        t.toAccountId,
        t.amountCents,
        t.feeCents,
        -1,
      );
    }
  });
  transfersVersion.value++;
  assetAccountsVersion.value++;
  BalanceHistoryService.instance.notifyChanged(fromId);
  BalanceHistoryService.instance.notifyChanged(toId);
}
