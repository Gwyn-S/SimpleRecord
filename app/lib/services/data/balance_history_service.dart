import 'package:sqflite/sqflite.dart';

import '../../utils/formatters.dart';
import '../core/database.dart';

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

  /// 快照数据版本：写操作投喂与重算落地各推进一次，供内存缓存判失效。
  int _version = 0;

  /// 进行中的重算（账户 → Future）。[ensureFresh] 用它等待，堵住
  /// "从 [_dirty] 取走到重算落地"的窗口：否则该窗口内 [_dirty] 已无此账户，
  /// 兜底会误判"已新鲜"直接返回，读到重算前的旧快照，随后又被重算结果覆盖，
  /// 走势图就会先出一版再跳一下。
  final Map<String, Future<void>> _inflight = {};

  /// [monthlyNetByYear] 结果缓存：key → (数据版本, 12 个月净值)。
  final Map<String, (int, List<int>)> _monthlyCache = {};

  Future<Database> get _db => DatabaseHelper.instance.database;

  /// 写时触发：将账户标记为待重算并投喂到串行异步队列（不阻塞调用方）。
  void notifyChanged(String? accountId) {
    if (accountId == null || accountId.isEmpty) return;
    _dirty.add(accountId);
    _version++;
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
        // 逐个取走：取走与登记 [_inflight] 之间不插入 await，
        // 保证 [ensureFresh] 看到的要么是"还在 _dirty"要么是"已登记在算"。
        final id = _dirty.first;
        _dirty.remove(id);
        try {
          await _runRecompute(id);
        } catch (_) {
          // 重算失败时把该账户放回待算队列，下次触发/兜底再试
          _dirty.add(id);
        }
      }
    } finally {
      _pumping = false;
    }
  }

  /// 执行重算并登记为进行中；同账户并发调用共享同一个 Future。
  Future<void> _runRecompute(String accountId) {
    final existing = _inflight[accountId];
    if (existing != null) return existing;
    final future = _recompute(accountId).whenComplete(() {
      _inflight.remove(accountId);
    });
    _inflight[accountId] = future;
    return future;
  }

  /// 读图兜底：若该账户还有未落地的重算（本机触发的或后台排队中的），
  /// 等它补齐后再返回，杜绝读到旧数据。
  Future<void> ensureFresh(String? accountId) async {
    if (accountId == null || accountId.isEmpty) return;
    final inflight = _inflight[accountId];
    if (inflight != null) {
      try {
        await inflight;
      } catch (_) {
        // 重算失败由后台队列放回重试；此处按"读当前数据"处理，
        // 与原先直读的行为一致，不额外向读取方抛错。
      }
      return;
    }
    if (!_dirty.remove(accountId)) return;
    await _runRecompute(accountId);
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

    // 有流水/调整的账户：整段重写，连"早于当前最早流水日"的历史残留也一并清掉。
    // 补录早期账、或改正错误日期后 startDay 会变晚，若只删 date>=startDay，
    // 旧起点之前的前缀会残留，导致走势图在真实期初前显示旧基数（期初漂移）。
    // 无流水/调整的账户期初无从重放，保持原行为（只重写 startDay 起的区间），
    // 避免误清其早期基线快照。
    final hasEvents = daily.isNotEmpty || adjustments.isNotEmpty;
    await db.transaction((txn) async {
      await txn.delete(
        'balance_snapshots',
        where: hasEvents ? 'account_id = ?' : 'account_id = ? AND date >= ?',
        whereArgs: hasEvents
            ? <Object?>[accountId]
            : <Object?>[accountId, startDay],
      );
      var running = opening;
      final buf = <Map<String, dynamic>>[];
      for (var day = startDay; day <= today; day++) {
        running += (daily[day] ?? 0) + (adjustments[day] ?? 0);
        buf.add({'account_id': accountId, 'date': day, 'balance': running});
      }
      await _batchInsert(txn, buf);
    });
    // 快照已落地，推进版本让走势图缓存失效。
    _version++;
  }

  /// 手动改余额：以"今天"为准使快照今日余额对齐 balance_cents。
  /// Δ 从今天生效（等价于今天插入一条对账调整，但不暴露给用户），
  /// 后续任何重算都会通过 [balance_adjustments] 复原该 Δ。
  Future<void> applyManualAdjustment(
    String accountId, {
    String sourceId = '',
    String operatorEmail = '',
  }) async {
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
      await recordAdjustment(
        accountId: accountId,
        date: today,
        deltaCents: delta,
        beforeCents: before,
        afterCents: current,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        sourceId: sourceId,
        operatorEmail: operatorEmail,
      );
    }
  }

  /// 金库记账/对端同步共用：把一条余额调整落库（仿手动调余额的历史记录），
  /// 让详情页流水可见。Δ 以 [date] 为准生效（记账日），供快照重算复原。
  /// [before]/[after] 仅作流水展示；快照用 delta。
  /// [sourceId] 为事件幂等键：非空时按 (account_id, source_id) 去重，
  /// 同一个 adjust 事件在本机只落一条（自己 push 的事件拉回也不会重复）。
  /// [recordKey] 为记账记录稳定键：非空时按 (account_id, record_key) 覆盖
  /// 更新（同一笔记账的 insert/update 都落在同一行，保证"一笔记账一条流水"，
  /// 删除时也能精确删掉对应的那一行）。[operatorEmail] 用于流水页展示"谁"调整/记账的。
  Future<void> recordAdjustment({
    required String accountId,
    required int date,
    required int deltaCents,
    required int beforeCents,
    required int afterCents,
    required int createdAt,
    String sourceId = '',
    String operatorEmail = '',
    String recordKey = '',
  }) async {
    final db = await _db;
    // Δ=0 的调整不落库：无实际余额变化，纯属噪音（如初始余额为 0 的 init 事件）。
    if (deltaCents == 0) return;
    // 手调/init 等无显式 record_key 的行，用 sourceId 作为稳定键回退，
    // 保证"删手调/删 init"在两端都能按 record_key 精确定位删除。
    final key = recordKey.isNotEmpty ? recordKey : sourceId;
    // 记账记录：按稳定键覆盖更新，保证一笔记账只占一行。
    if (key.isNotEmpty) {
      final existing = await db.query(
        'balance_adjustments',
        columns: ['id'],
        where: 'account_id = ? AND record_key = ?',
        whereArgs: [accountId, key],
      );
      final values = {
        'date': date,
        'delta': deltaCents,
        'before_cents': beforeCents,
        'after_cents': afterCents,
        'created_at': createdAt,
        'operator_email': operatorEmail,
      };
      if (existing.isNotEmpty) {
        await db.update(
          'balance_adjustments',
          values,
          where: 'account_id = ? AND record_key = ?',
          whereArgs: [accountId, key],
        );
      } else {
        await db.insert('balance_adjustments', {
          ...values,
          'account_id': accountId,
          'source_id': sourceId,
          'record_key': key,
        });
      }
      await _recompute(accountId);
      return;
    }
    await db.insert('balance_adjustments', {
      'account_id': accountId,
      'date': date,
      'delta': deltaCents,
      'before_cents': beforeCents,
      'after_cents': afterCents,
      'created_at': createdAt,
      'source_id': sourceId,
      'operator_email': operatorEmail,
    });
    await _recompute(accountId);
  }

  /// 删除一笔记账对应的调整记录（金库记账删除时调用）：
  /// 直接把该 record 关联的一行删掉，不追加反向记录。并重算该账户快照。
  Future<void> removeAdjustmentByRecordKey(
    String accountId,
    String recordKey,
  ) async {
    final db = await _db;
    await db.delete(
      'balance_adjustments',
      where: 'account_id = ? AND record_key = ?',
      whereArgs: [accountId, recordKey],
    );
    await _recompute(accountId);
  }

  /// 某账户的全部手动改余额记录（按日期升序），用于资产详情流水展示。
  Future<List<Map<String, dynamic>>> adjustmentsForAccount(
    String accountId,
  ) async {
    final db = await _db;
    return db.query(
      'balance_adjustments',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'date, created_at',
    );
  }

  /// 删除一条手动改余额/金库调整记录，还原账户余额，并重算该账户快照。
  /// 返回 (record_key, delta, newBalance)，供金库端联动云端删除事件；
  /// 行不存在返回 null。
  Future<({String recordKey, int delta, int newBalance})?> deleteAdjustment(
    String accountId,
    int id,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'balance_adjustments',
      columns: ['delta', 'record_key', 'source_id'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final delta = row['delta'] as int;
    await db.delete(
      'balance_adjustments',
      where: 'id = ?',
      whereArgs: [id],
    );
    final balance = await _readBalanceCents(db, accountId);
    final newBalance = balance - delta;
    await db.update(
      'asset_accounts',
      {'balance_cents': newBalance},
      where: 'id = ?',
      whereArgs: [accountId],
    );
    await _recompute(accountId);
    return (
      recordKey: (row['record_key']?.toString() ?? row['source_id']?.toString() ?? ''),
      delta: delta,
      newBalance: newBalance,
    );
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
  ///
  /// 结果与"逐月对每个账户各查一次最近快照"完全等价，但后者是
  /// 12×N 次串行往返（6 个账户 72 趟），这里先统一 [ensureFresh] 一次，
  /// 再用 2 次索引查询取出「年初前最近一条快照」与「年内全部快照」，
  /// 在内存里按月单调前推，压成 2 趟。
  Future<List<int>> monthlyNetByYear(
    int year,
    List<({String id, bool isDebt})> accounts,
  ) async {
    if (accounts.isEmpty) return List<int>.filled(12, 0);
    final key = _monthlyCacheKey(year, accounts);
    final hit = _monthlyCache[key];
    if (hit != null && hit.$1 == _version) return List<int>.from(hit.$2);

    for (final a in accounts) {
      await ensureFresh(a.id);
    }
    // 版本在补算之后取：补算本身会推进版本，取早了会导致结果永远存不进缓存。
    final version = _version;

    final db = await _db;
    final ids = [for (final a in accounts) a.id];
    final placeholders = List.filled(ids.length, '?').join(', ');
    final yearStart = toEpochDay(DateTime(year, 1, 1));
    final yearEnd = toEpochDay(DateTime(year, 12, 31));

    // 各账户在年初前最近的一条快照：全年各月末前推的基线（无则该账户计 0）。
    final headRows = await db.rawQuery(
      'SELECT s.account_id, s.date, s.balance '
      'FROM balance_snapshots AS s '
      'JOIN (SELECT account_id, MAX(date) AS d FROM balance_snapshots '
      '      WHERE account_id IN ($placeholders) AND date < ? '
      '      GROUP BY account_id) AS m '
      'ON m.account_id = s.account_id AND m.d = s.date',
      <Object?>[...ids, yearStart],
    );
    // 年内全部快照：逐月末前推时逐段消费。
    final yearRows = await db.query(
      'balance_snapshots',
      columns: ['account_id', 'date', 'balance'],
      where: 'account_id IN ($placeholders) AND date >= ? AND date <= ?',
      whereArgs: <Object?>[...ids, yearStart, yearEnd],
    );

    final byAccount = <String, List<(int, int)>>{};
    void collect(Map<String, Object?> row) {
      final id = row['account_id'] as String;
      (byAccount[id] ??= []).add((row['date'] as int, row['balance'] as int));
    }

    for (final r in headRows) {
      collect(r);
    }
    for (final r in yearRows) {
      collect(r);
    }
    for (final series in byAccount.values) {
      series.sort((a, b) => a.$1.compareTo(b.$1));
    }

    final result = List<int>.filled(12, 0);
    final cursors = <String, int>{};
    for (var m = 1; m <= 12; m++) {
      final day = toEpochDay(DateTime(year, m + 1, 0));
      var net = 0;
      for (final a in accounts) {
        final series = byAccount[a.id];
        if (series == null) continue;
        var i = cursors[a.id] ?? 0;
        var balance = 0;
        while (i < series.length && series[i].$1 <= day) {
          balance = series[i].$2;
          i++;
        }
        cursors[a.id] = i;
        net += a.isDebt ? -balance.abs() : balance;
      }
      result[m - 1] = net;
    }

    if (version == _version) {
      _monthlyCache[key] = (version, result);
      if (_monthlyCache.length > 32) _monthlyCache.clear();
    }
    return result;
  }

  /// 同步取 [monthlyNetByYear] 的缓存结果；未命中返回 null。
  ///
  /// 供走势图在切类型/切年份时同步画出新曲线，避免"等一个异步往返
  /// 导致旧曲线或占位线先闪一帧"。
  List<int>? monthlyNetByYearCached(
    int year,
    List<({String id, bool isDebt})> accounts,
  ) {
    if (accounts.isEmpty) return List<int>.filled(12, 0);
    final hit = _monthlyCache[_monthlyCacheKey(year, accounts)];
    if (hit == null || hit.$1 != _version) return null;
    return List<int>.from(hit.$2);
  }

  /// 缓存键含账户集合与年份；账户顺序无关（排序后拼接）。
  String _monthlyCacheKey(int year, List<({String id, bool isDebt})> accounts) {
    final parts = [for (final a in accounts) '${a.id}:${a.isDebt ? 1 : 0}']
      ..sort();
    return '$year#${parts.join(',')}';
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

    // 小金库账户的余额变化统一由 balance_adjustments 承载（记账/调余
    // 额都归一化为调整记录），快照重算这里跳过 records，避免计入两次。
    final accRows = await db.query(
      'asset_accounts',
      columns: ['category_name'],
      where: 'id = ?',
      whereArgs: [accountId],
    );
    final isVault =
        accRows.isNotEmpty && accRows.first['category_name'] == '小金库';
    if (!isVault) {
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
    if (rows.isEmpty) return;
    // 逐条 insert 每条都是一趟 IPC 往返：从最早流水日重写到今天的历史，
    // 三年就是上千趟。收进一个 Batch 在事务内一次提交，原子性与语义不变
    // （事务里的 batch 随事务一起生效），只是把上千趟压成一趟。
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'balance_snapshots',
        r,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
