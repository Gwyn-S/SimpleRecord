import 'package:sqflite/sqflite.dart';

import '../utils/formatters.dart';
import 'database.dart';

/// 逐日余额快照维护。
///
/// 设计口径（A）：
///  - records 与 transfers 是"真相"，balance_snapshots 只是结果缓存（可整表重建）。
///  - 期初 opening_balance_cents 在"最早关联该账户的流水日"计入，该日之前余额为 0。
///  - 余额 = 期初 + 逐日流水代数和（收入 +、支出 -、转出 -(金额+手续费)、转入 +金额）。
///  - 任何写操作（记账/转账/手动改余额）后调用 [notifyChanged]，账户快照在
///    串行异步队列中重算；重算在事务内"整段从最早流水日重写到今天"，保证
///    补录早期账/改中间日期/换账户/账户关联开合等所有情形都正确。
///  - 读走势图前调用 [ensureFresh] 兜底：若该账户尚未重算完则同步补算，杜绝读到旧数据。
class BalanceHistoryService {
  BalanceHistoryService._();
  static final BalanceHistoryService instance = BalanceHistoryService._();

  final Set<String> _dirty = {};
  bool _pumping = false;

  Future<Database> get _db => DatabaseHelper.instance.database;

  /// 写时触发：将账户标记为待重算并投喂到串行异步队列（不阻塞调用方）。
  void notifyChanged(String? accountId) {
    if (accountId == null || accountId.isEmpty) return;
    _dirty.add(accountId);
    _pump();
  }

  void _pump() {
    if (_pumping) return;
    _pumping = true;
    _pumpLoop();
  }

  Future<void> _pumpLoop() async {
    try {
      while (_dirty.isNotEmpty) {
        final ids = _dirty.toList();
        _dirty.clear();
        for (final id in ids) {
          try {
            await _recompute(id);
          } catch (_) {
            // 重算失败时把该账户放回待算队列，下次触发/兜底再试
            _dirty.add(id);
          }
        }
      }
    } finally {
      _pumping = false;
    }
  }

  /// 读图兜底：若该账户还有未落地的重算，立即同步补齐后再返回。
  Future<void> ensureFresh(String? accountId) async {
    if (accountId == null || accountId.isEmpty) return;
    if (!_dirty.remove(accountId)) return;
    await _recompute(accountId);
  }

  /// 从最早流水日到"今天"整段重写该账户的快照（期初计入最早流水日）。
  /// 手动改余额产生的 [balance_adjustments] 会按日叠加进余额，保证任何重算
  /// 都能复原手动调整对历史曲线的影响（异步重算不会把它冲掉）。
  Future<void> _recompute(String accountId) async {
    final db = await _db;
    final daily = await _dailyEvents(db, accountId);
    final adjustments = await _adjustmentsByDay(db, accountId);
    final today = toEpochDay(DateTime.now());

    final opening = await _readOpening(db, accountId);
    var startDay = today;
    for (final day in daily.keys) {
      if (day < startDay) startDay = day;
    }
    for (final day in adjustments.keys) {
      if (day < startDay) startDay = day;
    }

    await db.transaction((txn) async {
      await txn.delete(
        'balance_snapshots',
        where: 'account_id = ? AND date >= ?',
        whereArgs: [accountId, startDay],
      );
      var running = opening;
      final buf = <Map<String, dynamic>>[];
      for (var day = startDay; day <= today; day++) {
        running += (daily[day] ?? 0) + (adjustments[day] ?? 0);
        buf.add({'account_id': accountId, 'date': day, 'balance': running});
      }
      await _batchInsert(txn, buf);
    });
  }

  /// 手动改余额：以"今天"为准使快照今日余额对齐 balance_cents。
  /// Δ 从今天生效（等价于今天插入一条对账调整，但不暴露给用户），
  /// 后续任何重算都会通过 [balance_adjustments] 复原该 Δ。
  Future<void> applyManualAdjustment(String accountId) async {
    final db = await _db;
    await _recompute(accountId);
    final today = toEpochDay(DateTime.now());
    final current = await _readBalanceCents(db, accountId);
    final rows = await db.query(
      'balance_snapshots',
      columns: ['balance'],
      where: 'account_id = ? AND date = ?',
      whereArgs: [accountId, today],
    );
    final before = rows.isEmpty ? 0 : rows.first['balance'] as int;
    final delta = current - before;
    if (delta != 0) {
      await db.insert('balance_adjustments', {
        'account_id': accountId,
        'date': today,
        'delta': delta,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await _recompute(accountId);
    }
  }

  /// 查询某账户在 [fromDay, toDay]（含）各天的余额；该范围之前无快照的天补 0。
  Future<Map<int, int>> balancesForAccount(
    String accountId,
    int fromDay,
    int toDay,
  ) async {
    await ensureFresh(accountId);
    final db = await _db;
    final rows = await db.query(
      'balance_snapshots',
      columns: ['date', 'balance'],
      where: 'account_id = ? AND date >= ? AND date <= ?',
      whereArgs: [accountId, fromDay, toDay],
    );
    return {for (final r in rows) r['date'] as int: r['balance'] as int};
  }

  /// 计算 [accounts] 中各账户在指定日的余额（前推最近快照，早于期初为 0）。
  Future<Map<String, int>> balancesAt(
    List<({String id, bool isDebt})> accounts,
    int day,
  ) async {
    final db = await _db;
    final result = <String, int>{};
    for (final a in accounts) {
      await ensureFresh(a.id);
      final rows = await db.query(
        'balance_snapshots',
        columns: ['balance'],
        where: 'account_id = ? AND date <= ?',
        whereArgs: [a.id, day],
        orderBy: 'date DESC',
        limit: 1,
      );
      result[a.id] = rows.isEmpty ? 0 : rows.first['balance'] as int;
    }
    return result;
  }

  /// 某年各月末的净资产曲线：资产账户求和减负债账户（负债取绝对值）。
  /// 返回 1..12 每月的月末净资产；早于该账户期初的月份计为 0。
  Future<List<int>> monthlyNetByYear(
    int year,
    List<({String id, bool isDebt})> accounts,
  ) async {
    final result = <int>[];
    for (var m = 1; m <= 12; m++) {
      final day = toEpochDay(DateTime(year, m + 1, 0));
      final bal = await balancesAt(accounts, day);
      var net = 0;
      for (final a in accounts) {
        final b = bal[a.id] ?? 0;
        net += a.isDebt ? -b.abs() : b;
      }
      result.add(net);
    }
    return result;
  }

  // ========================= 内部工具 =========================

  /// 汇总某账户每天的收支代数和（含转账），返回 日→净额。
  Future<Map<int, int>> _dailyEvents(
    DatabaseExecutor db,
    String accountId,
  ) async {
    final daily = <int, int>{};
    void add(int day, int delta) =>
        daily.update(day, (v) => v + delta, ifAbsent: () => delta);

    final records = await db.query(
      'records',
      columns: ['date', 'is_expense', 'amount_cents'],
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    for (final r in records) {
      final isExpense = r['is_expense'] == 1;
      final amount = r['amount_cents'] as int;
      add(r['date'] as int, isExpense ? -amount : amount);
    }

    final fromRows = await db.query(
      'transfers',
      columns: ['date', 'amount_cents', 'fee_cents'],
      where: 'from_account_id = ?',
      whereArgs: [accountId],
    );
    for (final r in fromRows) {
      add(
        r['date'] as int,
        -((r['amount_cents'] as int) + (r['fee_cents'] as int)),
      );
    }

    final toRows = await db.query(
      'transfers',
      columns: ['date', 'amount_cents'],
      where: 'to_account_id = ?',
      whereArgs: [accountId],
    );
    for (final r in toRows) {
      add(r['date'] as int, r['amount_cents'] as int);
    }

    return daily;
  }

  /// 按日聚合手动改余额的 Δ，返回 日→累计Δ。
  Future<Map<int, int>> _adjustmentsByDay(
    DatabaseExecutor db,
    String accountId,
  ) async {
    final rows = await db.query(
      'balance_adjustments',
      columns: ['date', 'delta'],
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    final byDay = <int, int>{};
    for (final r in rows) {
      final day = r['date'] as int;
      byDay.update(
        day,
        (v) => v + (r['delta'] as int),
        ifAbsent: () => r['delta'] as int,
      );
    }
    return byDay;
  }

  Future<int> _readOpening(DatabaseExecutor db, String accountId) async {
    final rows = await db.query(
      'asset_accounts',
      columns: ['opening_balance_cents'],
      where: 'id = ?',
      whereArgs: [accountId],
    );
    return rows.isEmpty ? 0 : (rows.first['opening_balance_cents'] as int);
  }

  Future<int> _readBalanceCents(DatabaseExecutor db, String accountId) async {
    final rows = await db.query(
      'asset_accounts',
      columns: ['balance_cents'],
      where: 'id = ?',
      whereArgs: [accountId],
    );
    return rows.isEmpty ? 0 : (rows.first['balance_cents'] as int);
  }

  Future<void> _batchInsert(
    DatabaseExecutor db,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final r in rows) {
      await db.insert(
        'balance_snapshots',
        r,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
