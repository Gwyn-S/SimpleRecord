import 'package:sqflite/sqflite.dart';

import '../../utils/formatters.dart';
import '../core/database.dart';

/// 余额历史维护。
///
/// 设计口径：
///  - records 与 transfers 是"真相"，balance_snapshots 只写"账户起点 + 每月末"锚点。
///  - 期初 opening_balance_cents 从账户创建日计入（有更早的补录流水则从最早流水日计入），之前余额为 0。
///  - 余额 = 期初 + 逐日流水代数和（收入 +、支出 -、转出 -(金额+手续费)、转入 +金额）。
///  - 任意日余额由"最近锚点 + 区间流水"前推得到。
///  - 任何写操作（记账/转账/手动改余额）后调用 [notifyChanged]，账户锚点在
///    串行异步队列中重算；重算在事务内"整段从创建日重写到今天"，保证
///    补录早期账/改中间日期/换账户/账户关联开合等所有情形都正确。
///  - 读走势图前调用 [ensureFresh] 兜底：若该账户尚未重算完则同步补算，杜绝读到旧数据。
class BalanceHistoryService {
  BalanceHistoryService._();
  static final BalanceHistoryService instance = BalanceHistoryService._();

  final Set<String> _dirty = {};
  bool _pumping = false;

  /// 快照数据版本：写操作投喂与重算落地各推进一次，供内存缓存判失效。
  int _version = 0;

  /// 各账户锚点已覆盖到的最近月末（epoch day）。内存为空时由
  /// [_coveredThrough] 从库里快照推导回填。
  final Map<String, int> _anchoredThrough = {};

  /// 进行中的重算（账户 → Future）。[ensureFresh] 用它等待，堵住
  /// "从 [_dirty] 取走到重算落地"的窗口：否则该窗口内 [_dirty] 已无此账户，
  /// 兜底会误判"已新鲜"直接返回，读到重算前的旧快照，随后又被重算结果覆盖，
  /// 走势图就会先出一版再跳一下。
  final Map<String, Future<void>> _inflight = {};

  /// [monthlyNetByYear] 结果缓存：key → (数据版本, 算取日, 12 个月净值)。
  /// 隔天不判死，由调用方拿算取日决定是否后台静默刷新。
  final Map<String, (int, int, List<int>)> _monthlyCache = {};

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
  Future<void> ensureFresh(String accountId) async {
    final inflight = _inflight[accountId];
    if (inflight != null) {
      try {
        await inflight;
      } catch (_) {
        // 失败不抛给读取方，按当前数据返回；后台队列会重试。
      }
      return;
    }
    if (_dirty.remove(accountId)) {
      try {
        await _runRecompute(accountId);
      } catch (_) {
        // 直算失败：放回队列让后台重试，不向读取方抛错。
        _dirty.add(accountId);
        _pump();
      }
      return;
    }
    final today = toEpochDay(DateTime.now());
    if (await _coveredThrough(accountId) == _lastMonthEnd(today)) return;
    await _runRecompute(accountId);
  }

  /// 该账户锚点已覆盖到的最近月末（epoch day）。
  /// 内存为空时从库推导并回填：最大快照日是月末就取它，否则取该日之前
  /// 最近的月末（起点锚/旧版逐日快照）；无快照返回 0 触发补算。
  Future<int> _coveredThrough(String accountId) async {
    final cached = _anchoredThrough[accountId];
    if (cached != null) return cached;
    final db = await _db;
    final rows = await db.query(
      'balance_snapshots',
      columns: ['MAX(date) AS max_date'],
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    final maxDate = rows.isEmpty ? null : rows.first['max_date'] as int?;
    final covered = maxDate == null ? 0 : _lastMonthEnd(maxDate);
    _anchoredThrough[accountId] = covered;
    return covered;
  }

  /// 从创建日（或更早的补录流水日）到"今天"整段重写该账户的锚点。
  /// 手动改余额产生的 [balance_adjustments] 会按日叠加进余额，保证任何重算
  /// 都能复原手动调整对历史曲线的影响（异步重算不会把它冲掉）。
  Future<void> _recompute(String accountId) async {
    final db = await _db;
    final acc = await _readAccountAmounts(db, accountId);
    if (acc == null) return;
    final deltas = await _dailyDeltas(db, accountId, isVault: acc.isVault);
    final today = toEpochDay(DateTime.now());
    final startDay = _seriesStartDay(acc.createdAt, deltas, today);

    // 锚点完全由"起点 + 流水"重放，整段删掉重写，补录早期账或删流水都不会残留旧锚点。
    await db.transaction((txn) async {
      await txn.delete(
        'balance_snapshots',
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
      final buf = <Map<String, dynamic>>[];
      _walkBalances(
        opening: acc.opening,
        startDay: startDay,
        today: today,
        deltas: deltas,
        visit: (day, balance) {
          if (day == startDay || _isMonthEnd(day)) {
            buf.add({'account_id': accountId, 'date': day, 'balance': balance});
          }
        },
      );
      await _batchInsert(txn, buf);
    });
    // 锚点已落地，推进版本让走势图/月度缓存失效。
    _version++;
    _anchoredThrough[accountId] = _lastMonthEnd(today);
  }

  /// 不晚于 [today] 的最近一个月末；[day] 本身是月末时返回其自身。
  int _lastMonthEnd(int today) {
    final d = fromEpochDay(today);
    final end = toEpochDay(DateTime(d.year, d.month + 1, 0));
    return end <= today ? end : toEpochDay(DateTime(d.year, d.month, 0));
  }

  /// [day] 是否为月末，复用 [_lastMonthEnd] 的日期运算。
  bool _isMonthEnd(int day) => day == _lastMonthEnd(day);

  /// 手动改余额：以"今天"为准使余额对齐 balance_cents。
  /// Δ 从今天生效（等价于今天插入一条对账调整，但不暴露给用户），
  /// 后续任何重算都会通过 [balance_adjustments] 复原该 Δ。
  /// Δ 由"期初 + 截至今日流水代数和"内存算出（与锚点链等价），不为读这
  /// 一个数先整段重算；唯一的重算发生在 [recordAdjustment] 落库之后。
  Future<void> applyManualAdjustment(
    String accountId, {
    String sourceId = '',
    String operatorEmail = '',
  }) async {
    final db = await _db;
    final acc = await _readAccountAmounts(db, accountId);
    if (acc == null) return;
    final today = toEpochDay(DateTime.now());
    final deltas = await _dailyDeltas(db, accountId, isVault: acc.isVault);
    var before = acc.opening;
    for (final (day, d) in deltas) {
      if (day <= today) before += d;
    }
    final delta = acc.balance - before;
    if (delta != 0) {
      await recordAdjustment(
        accountId: accountId,
        date: today,
        deltaCents: delta,
        beforeCents: before,
        afterCents: acc.balance,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        sourceId: sourceId,
        operatorEmail: operatorEmail,
      );
    }
  }

  /// 行结果化底层（事务级）：把 (account_id, 幂等键) 的调整行置为目标态。
  /// 幂等键 = recordKey 优先，空则 sourceId 去重；均为空时直插。
  /// deltaCents == 0 = 撤销：删旧行，不落 0 值行。
  /// 返回余额缓存净变化（新行 delta − 旧行 delta，重复应用同值 = 0）；
  /// 调用方负责把返回值写入 balance_cents 并事后调用 [notifyChanged]。
  Future<int> applyFlowRow(
    DatabaseExecutor db, {
    required String accountId,
    String sourceId = '',
    String recordKey = '',
    required int deltaCents,
    int date = 0,
    int createdAt = 0,
    String operatorEmail = '',
    int beforeCents = 0,
    int afterCents = 0,
  }) async {
    final key = recordKey.isNotEmpty ? recordKey : sourceId;
    // 读旧行 delta，用于计算缓存净变化。
    Map<String, Object?>? existing;
    if (key.isNotEmpty) {
      final rows = await db.query(
        'balance_adjustments',
        where: 'account_id = ? AND record_key = ?',
        whereArgs: [accountId, key],
      );
      if (rows.isNotEmpty) existing = rows.first;
    }
    final oldDelta =
        existing == null ? 0 : (existing['delta'] as num? ?? 0).toInt();

    // 目标态 0 = 撤销：删行。
    if (deltaCents == 0) {
      if (existing != null) {
        await db.delete(
          'balance_adjustments',
          where: 'account_id = ? AND record_key = ?',
          whereArgs: [accountId, key],
        );
        return -oldDelta;
      }
      return 0;
    }

    final values = <String, dynamic>{
      'date': date,
      'delta': deltaCents,
      'before_cents': beforeCents,
      'after_cents': afterCents,
      'created_at': createdAt,
      'operator_email': operatorEmail,
    };
    if (key.isNotEmpty && existing != null) {
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
    // 新建 = 全额、覆盖 = 差额、重复应用同值 = 0。
    return deltaCents - oldDelta;
  }

  /// 撤销一条调整行（事务级）：删行并返回缓存回退量（−旧行 delta，
  /// 行不存在返回 0）。不写余额、不通知快照，由调用方收口；重复调用幂等。
  Future<int> revokeFlowRow(
    DatabaseExecutor db, {
    required String accountId,
    required String recordKey,
  }) async {
    final rows = await db.query(
      'balance_adjustments',
      columns: ['delta'],
      where: 'account_id = ? AND record_key = ?',
      whereArgs: [accountId, recordKey],
    );
    if (rows.isEmpty) return 0;
    final oldDelta = (rows.first['delta'] as num? ?? 0).toInt();
    await db.delete(
      'balance_adjustments',
      where: 'account_id = ? AND record_key = ?',
      whereArgs: [accountId, recordKey],
    );
    return -oldDelta;
  }

  /// 金库余额校准：按快照同口径（opening + adjustments + transfers）从流水
  /// 重放终值写回 balance_cents。低频动作，vault_ops 批尾收口用，
  /// 日常记账走行驱动增量不走这里。
  Future<void> recalcVaultBalance(String accountId) async {
    final db = await _db;
    final acc = await _readAccountAmounts(db, accountId);
    if (acc == null || !acc.isVault) return;
    final today = toEpochDay(DateTime.now());
    final deltas = await _dailyDeltas(db, accountId, isVault: true);
    var balance = acc.opening;
    for (final (day, d) in deltas) {
      if (day <= today) balance += d;
    }
    await db.update(
      'asset_accounts',
      {'balance_cents': balance},
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  /// 金库记账/对端同步共用：把一条余额调整落库（仿手动调余额的历史记录），
  /// 让详情页流水可见。Δ 以 [date] 为准生效（记账日），供快照重算复原。
  /// 锚点交给 [notifyChanged] 队列异步重算。
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
    // Δ=0 不落库（无余额变化的噪音）；撤销语义不走这里，见 applyFlowRow。
    if (deltaCents == 0) return;
    await applyFlowRow(
      await _db,
      accountId: accountId,
      sourceId: sourceId,
      recordKey: recordKey,
      deltaCents: deltaCents,
      date: date,
      createdAt: createdAt,
      operatorEmail: operatorEmail,
      beforeCents: beforeCents,
      afterCents: afterCents,
    );
    notifyChanged(accountId);
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

  /// 删除一条手动改余额/金库调整记录，还原账户余额；锚点交给
  /// [notifyChanged] 异步重算。返回 (record_key, delta, newBalance)，
  /// 供金库端联动云端删除事件；行不存在返回 null。
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
    await db.delete('balance_adjustments', where: 'id = ?', whereArgs: [id]);
    final acc = await _readAccountAmounts(db, accountId);
    if (acc == null) return null;
    final newBalance = acc.balance - delta;
    await db.update(
      'asset_accounts',
      {'balance_cents': newBalance},
      where: 'id = ?',
      whereArgs: [accountId],
    );
    notifyChanged(accountId);
    return (
      recordKey: (row['record_key'] as String).isNotEmpty
          ? row['record_key'] as String
          : row['source_id'] as String,
      delta: delta,
      newBalance: newBalance,
    );
  }

  /// 该账户从创建日到今天的逐日余额（供走势图一次性预取）。
  Future<Map<int, int>> fullDailyBalances(String accountId) async {
    await ensureFresh(accountId);
    final db = await _db;
    final acc = await _readAccountAmounts(db, accountId);
    if (acc == null) return const {};
    final deltas = await _dailyDeltas(db, accountId, isVault: acc.isVault);
    final today = toEpochDay(DateTime.now());
    final result = <int, int>{};
    _walkBalances(
      opening: acc.opening,
      startDay: _seriesStartDay(acc.createdAt, deltas, today),
      today: today,
      deltas: deltas,
      visit: (day, balance) => result[day] = balance,
    );
    return result;
  }

  /// 曲线起点：创建日与最早流水日取早者，且不晚于今天。
  int _seriesStartDay(int createdAtMs, List<(int, int)> deltas, int today) {
    final created = toEpochDay(
      DateTime.fromMillisecondsSinceEpoch(createdAtMs),
    );
    final first = deltas.isNotEmpty ? deltas.first.$1 : created;
    final start = created < first ? created : first;
    return start < today ? start : today;
  }

  /// 从期初开始按日展开 [startDay, today] 的余额并逐日回调。
  void _walkBalances({
    required int opening,
    required int startDay,
    required int today,
    required List<(int, int)> deltas,
    required void Function(int day, int balance) visit,
  }) {
    var running = opening;
    var index = 0;
    for (var day = startDay; day <= today; day++) {
      while (index < deltas.length && deltas[index].$1 <= day) {
        running += deltas[index].$2;
        index++;
      }
      visit(day, running);
    }
  }

  /// 指定日余额：最近锚点 + 区间流水前推。
  Future<int> _balanceAtDay(
    DatabaseExecutor db,
    String accountId,
    int day, {
    required bool isVault,
  }) async {
    final rows = await db.query(
      'balance_snapshots',
      columns: ['date', 'balance'],
      where: 'account_id = ? AND date <= ?',
      whereArgs: [accountId, day],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    final baseDay = rows.first['date'] as int;
    var balance = rows.first['balance'] as int;
    if (baseDay == day) return balance;
    final deltas = await _dailyDeltas(
      db,
      accountId,
      isVault: isVault,
      fromExclusive: baseDay,
      toInclusive: day,
    );
    for (final d in deltas) {
      balance += d.$2;
    }
    return balance;
  }

  /// 某年各月末的净资产曲线：资产账户求和减负债账户（负债取绝对值）。
  /// 返回 1..12 每月的月末净资产；早于该账户期初的月份计为 0。
  ///
  /// 结果与"逐月对每个账户各查一次最近快照"完全等价，但后者是
  /// 12×N 次串行往返（6 个账户 72 趟），这里先统一 [ensureFresh] 一次，
  /// 再用 2 次索引查询取出「年初前最近一条快照」与「年内全部快照」，
  /// 在内存里按月单调前推；仅当年多出 N 次 [_balanceAtDay]（当月现算）。
  Future<List<int>> monthlyNetByYear(
    int year,
    List<({String id, bool isDebt, bool isVault})> accounts,
  ) async {
    if (accounts.isEmpty) return List<int>.filled(12, 0);
    final key = _monthlyCacheKey(year, accounts);
    final today = toEpochDay(DateTime.now());
    final hit = _monthlyCache[key];
    if (hit != null && hit.$1 == _version && hit.$2 == today) {
      return List<int>.from(hit.$3);
    }

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

    // 当月没有月末锚点，用"上月末锚点 + 本月至今流水"现算。
    final now = DateTime.now();
    final isCurrentYear = year == now.year;
    final currentMonth = now.month;
    final todayBalances = <String, int>{};
    if (isCurrentYear) {
      for (final a in accounts) {
        todayBalances[a.id] = await _balanceAtDay(
          db,
          a.id,
          toEpochDay(now),
          isVault: a.isVault,
        );
      }
    }

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
        int balance;
        if (isCurrentYear && m == currentMonth) {
          balance = todayBalances[a.id]!;
        } else {
          final series = byAccount[a.id];
          if (series == null) continue;
          var i = cursors[a.id] ?? 0;
          balance = 0;
          while (i < series.length && series[i].$1 <= day) {
            balance = series[i].$2;
            i++;
          }
          cursors[a.id] = i;
        }
        net += a.isDebt ? -balance.abs() : balance;
      }
      result[m - 1] = net;
    }

    if (version == _version) {
      _monthlyCache[key] = (version, today, result);
      if (_monthlyCache.length > 32) _monthlyCache.clear();
    }
    return result;
  }

  /// 同步取缓存结果及算取日；未命中返回 null。只拦版本不一致，不按天
  /// 判失效——调用方用算取日决定是否后台静默刷新。
  ({List<int> months, int cachedDay})? monthlyNetByYearCached(
    int year,
    List<({String id, bool isDebt, bool isVault})> accounts,
  ) {
    final hit = _monthlyCache[_monthlyCacheKey(year, accounts)];
    if (hit == null || hit.$1 != _version) return null;
    return (months: List<int>.from(hit.$3), cachedDay: hit.$2);
  }

  /// 缓存键含账户集合与年份；账户顺序无关（排序后拼接）。
  String _monthlyCacheKey(
    int year,
    List<({String id, bool isDebt, bool isVault})> accounts,
  ) {
    final parts = [
      for (final a in accounts)
        '${a.id}:${a.isDebt ? 1 : 0}:${a.isVault ? 1 : 0}',
    ]..sort();
    return '$year#${parts.join(',')}';
  }

  // ========================= 内部工具 =========================

  /// 汇总某账户按日的净变动（records + transfers + balance_adjustments），按日期升序。
  /// 小金库账户跳过 records（余额只由 balance_adjustments 承载）；
  /// 转出扣金额+手续费，转入只加金额；不按 book_id 过滤。
  Future<List<(int, int)>> _dailyDeltas(
    DatabaseExecutor db,
    String accountId, {
    required bool isVault,
    int? fromExclusive,
    int? toInclusive,
  }) async {
    String range(String column) {
      final buf = StringBuffer();
      if (fromExclusive != null) buf.write(' AND $column > ?');
      if (toInclusive != null) buf.write(' AND $column <= ?');
      return buf.toString();
    }

    final rangeArgs = [?fromExclusive, ?toInclusive];

    final selects = <String>[];
    final args = <Object?>[];

    void addSelect(String sql, List<Object?> selectArgs) {
      selects.add(sql);
      args.addAll(selectArgs);
    }

    if (!isVault) {
      addSelect(
        'SELECT date, CASE WHEN is_expense = 1 '
        'THEN -amount_cents ELSE amount_cents END AS delta '
        'FROM records WHERE account_id = ?${range('date')}',
        <Object?>[accountId, ...rangeArgs],
      );
    }
    addSelect(
      'SELECT date, -(amount_cents + fee_cents) AS delta FROM transfers '
      'WHERE from_account_id = ?${range('date')}',
      <Object?>[accountId, ...rangeArgs],
    );
    addSelect(
      'SELECT date, amount_cents AS delta FROM transfers '
      'WHERE to_account_id = ?${range('date')}',
      <Object?>[accountId, ...rangeArgs],
    );
    addSelect(
      'SELECT date, delta FROM balance_adjustments '
      'WHERE account_id = ?${range('date')}',
      <Object?>[accountId, ...rangeArgs],
    );

    final rows = await db.rawQuery(
      'SELECT date, SUM(delta) AS delta FROM ('
      '${selects.join(' UNION ALL ')}'
      ') GROUP BY date ORDER BY date',
      args,
    );
    return [for (final r in rows) (r['date'] as int, r['delta'] as int)];
  }

  /// 读取账户的 (期初, 当前余额, 创建时间, 是否小金库)；账户不存在返回 null。
  Future<({int opening, int balance, int createdAt, bool isVault})?>
  _readAccountAmounts(DatabaseExecutor db, String accountId) async {
    final rows = await db.query(
      'asset_accounts',
      columns: [
        'opening_balance_cents',
        'balance_cents',
        'created_at',
        'category_name',
      ],
      where: 'id = ?',
      whereArgs: [accountId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      opening: row['opening_balance_cents'] as int,
      balance: row['balance_cents'] as int,
      createdAt: row['created_at'] as int,
      isVault: row['category_name'] == '小金库',
    );
  }

  Future<void> _batchInsert(
    DatabaseExecutor db,
    List<Map<String, dynamic>> rows,
  ) async {
    // 锚点只有"起点 + 每月末"，几十行，收进一个 batch 随事务一次提交。
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
