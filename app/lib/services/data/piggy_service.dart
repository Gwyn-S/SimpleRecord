import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/data/piggy.dart';
import '../../models/data/record.dart';
import '../../utils/id.dart';
import '../cloud/supabase_service.dart';
import '../core/author_service.dart';
import '../core/cloud_config.dart';
import '../core/database.dart';
import 'record_service.dart';

/// 加入小金库失败细分原因。
enum JoinPiggyResult { notReady, inviteInvalid, joinFailed, success }

enum PiggyCreateResult { notSignedIn, serverFailed, success }

/// 小金库引擎：全局共享资产的云端 append-only 事件同步。
///
/// 架构与 [SyncService] 对齐：操作恒为"在线操作"（失败直接报错重试，不用 outbox），
/// 云端 append 成功拿到 op_id 后才落本地 piggy_events（op_id 幂等），再推进
/// 同步位点（sync_state key: piggy_cursor:{piggyId}）。
/// 下行增量拉取跳过本机 device_id 的事件（防回声），跨设备全量重放恢复余额。
class PiggyService {
  PiggyService._();

  static final PiggyService instance = PiggyService._();

  bool _started = false;
  String? _deviceId;

  /// 当前已订阅实时通道的金库 id 集合（stop 时逐个退订）。
  final Set<String> _subscribed = {};

  bool get isStarted => _started;

  /// 小金库仓库变化（列表/余额/流水）刷新信号，供各页面监听。
  final ValueNotifier<int> piggyVersion = ValueNotifier(0);

  // ==================== 生命周期 ====================

  /// 启动：确认云端就绪并已登录 → 恢复我参与的金库 → 订阅实时通道 → 并发拉取。
  /// 幂等：已在运行时直接返回 true；未配置/未登录时静默返回 false。
  Future<bool> start() async {
    if (_started) return true;
    await SupabaseManager.instance.init();
    if (!SupabaseManager.instance.isReady) return false;
    if (!await SupabaseManager.instance.ensureSignedIn()) return false;
    _deviceId = await getOrCreateDeviceId();
    _started = true;
    await _restoreMyPiggies();
    await _subscribeAll();
    await pullAllPiggy();
    return true;
  }

  /// 停止：退订全部金库实时通道并复位状态（登出时调用）。
  Future<void> stop() async {
    final supabase = SupabaseManager.instance;
    for (final id in _subscribed.toList()) {
      if (supabase.isReady) {
        await supabase.unsubscribePiggyOps(id);
      }
      _subscribed.remove(id);
    }
    _started = false;
  }

  // ==================== 我的金库 ====================

  /// 只返回我参与（owner 或 peer）的本地小金库，换号后不可见。
  Future<List<Piggy>> loadMyPiggies() async {
    final db = await DatabaseHelper.instance.database;
    final myEmail = SupabaseManager.instance.email ?? '';
    if (myEmail.isEmpty) return const [];
    final rows = await db.query(
      'piggies',
      where: 'owner_author_id = ? OR peer_author_id = ?',
      whereArgs: [myEmail, myEmail],
      orderBy: 'created_at ASC',
    );
    return rows.map(Piggy.fromDbMap).toList();
  }

  /// 按 id 查单个金库（无则 null）。
  Future<Piggy?> findPiggy(String piggyId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'piggies',
      where: 'id = ?',
      whereArgs: [piggyId],
      limit: 1,
    );
    return rows.isEmpty ? null : Piggy.fromDbMap(rows.first);
  }

  /// 以云端 piggy 表为权威源，把我参与的金库恢复到本地（换设备/清数据兜底）。
  /// 已存在的行整体替换（owner/peer/名称/invite 变化即更新）。
  Future<void> _restoreMyPiggies() async {
    final supabase = SupabaseManager.instance;
    final myEmail = supabase.email ?? '';
    if (myEmail.isEmpty) return;
    final piggies = await supabase.fetchMyPiggies();
    if (piggies.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    for (final row in piggies) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      await _upsertPiggy(db, Piggy(
        id: id,
        name: row['name']?.toString() ?? '小金库',
        ownerAuthorId: row['owner_email']?.toString(),
        peerAuthorId: row['peer_email']?.toString(),
        inviteCode: row['invite_code']?.toString() ?? '',
        createdAt: _parseEpochOrNull(row['created_at']) ??
            DateTime.now().millisecondsSinceEpoch,
      ));
    }
    if (piggies.isNotEmpty) piggyVersion.value++;
  }

  /// 订阅本地已存在的、我参与的全部金库并拉取增量（start 时调用）。
  Future<void> _subscribeAll() async {
    final piggies = await loadMyPiggies();
    for (final p in piggies) {
      await _subscribe(p.id);
    }
    await pullAllPiggy();
  }

  Future<void> _subscribe(String piggyId) async {
    if (_subscribed.contains(piggyId)) return;
    await SupabaseManager.instance.subscribePiggyOps(
      piggyId: piggyId,
      callback: _onPiggyOpInsert,
    );
    _subscribed.add(piggyId);
  }

  Future<void> _upsertPiggy(Database db, Piggy piggy) async {
    await db.insert(
      'piggies',
      piggy.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==================== 下行：增量拉取与应用 ====================

  /// 收到 piggy_ops INSERT 回调：按金库拉取增量。
  Future<void> _onPiggyOpInsert(PostgresChangePayload payload) async {
    if (!_started) return;
    final piggyId = payload.newRecord['piggy_id']?.toString();
    if (piggyId != null && piggyId.isNotEmpty) {
      await pullForPiggy(piggyId);
    }
  }

  /// 并发拉取我参与的全部金库增量。
  Future<void> pullAllPiggy() async {
    if (!_started) return;
    final piggies = await loadMyPiggies();
    await Future.wait(piggies.map((p) => pullForPiggy(p.id)));
  }

  /// 拉取单个金库增量：循环翻页直到追平，末尾整体推进位点。
  /// 幂等：重复应用按 op_id 唯一索引忽略；本机 device_id 事件跳过（防回声）。
  Future<void> pullForPiggy(String piggyId) async {
    if (!_started) return;
    final supabase = SupabaseManager.instance;
    final db = await DatabaseHelper.instance.database;
    var cursor = await _getCursor(piggyId);
    // 仅当本轮实际应用到远端变更时才广播版本号，避免空拉取引发全量重建。
    var appliedAny = false;
    while (true) {
      final ops = await supabase.fetchPiggyOps(
        piggyId,
        afterId: cursor,
        limit: 200,
      );
      if (ops.isEmpty) break;
      var maxId = cursor;
      for (final op in ops) {
        final id = (op['id'] as num?)?.toInt() ?? 0;
        if (id > maxId) maxId = id;
        final deviceId = op['device_id']?.toString();
        if (deviceId == _deviceId) continue;
        try {
          await _applyPiggyOp(db, piggyId, op);
          appliedAny = true;
        } catch (e) {
          // 单条应用失败不中断整批拉取：位点仍推进，靠 op_id 幂等在下次覆盖。
          debugPrint('[piggy] apply op failed: $e');
        }
      }
      await _setCursor(piggyId, maxId);
      cursor = maxId;
      if (ops.length < 200) break;
    }
    if (appliedAny) piggyVersion.value++;
  }

  /// 把一条云端 piggy_op 应用到本地 piggy_events。
  /// payload 约定：{piggy_id, delta(正=存 负=取), remark, operator_email}。
  Future<void> _applyPiggyOp(
    Database db,
    String piggyId,
    Map<String, dynamic> op,
  ) async {
    final id = (op['id'] as num?)?.toInt() ?? 0;
    if (id == 0) return;
    final payload = op['payload'];
    final payloadMap = payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
    final delta = (payloadMap['delta'] as num?)?.toInt() ??
        (op['delta'] as num?)?.toInt() ??
        0;
    final opName = (payloadMap['op'] as String?) ??
        (op['op']?.toString()) ??
        (delta >= 0 ? 'deposit' : 'withdraw');
    final remark = payloadMap['remark']?.toString() ?? '';
    final operatorEmail =
        payloadMap['operator_email']?.toString() ??
        op['operator_email']?.toString() ??
        '';
    await db.insert(
      'piggy_events',
      {
        'op_id': id,
        'piggy_id': piggyId,
        'op': opName,
        'delta': delta,
        'remark': remark,
        'operator_email': operatorEmail,
        'created_at':
            _parseEpochOrNull(op['created_at']) ??
            DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // ==================== 创建/加入 ====================

  /// 新建小金库：云端建行成功（拿到邀请码）后才落本地 + 订阅 + 拉取。
  /// 返回（结果, 邀请码）：仅 [PiggyCreateResult.success] 时邀请码非空（供分享）。
  Future<(PiggyCreateResult, String?)> createPiggy(String name) async {
    if (!_started && !await start()) return (PiggyCreateResult.notSignedIn, null);
    final supabase = SupabaseManager.instance;
    final myEmail = supabase.email;
    if (myEmail == null) return (PiggyCreateResult.notSignedIn, null);
    final piggyId = genId();
    final invite = _generateInviteCode();
    final code = await supabase.createPiggy(
      piggyId: piggyId,
      name: name,
      inviteCode: invite,
    );
    if (code == null) return (PiggyCreateResult.serverFailed, null);
    final db = await DatabaseHelper.instance.database;
    await _upsertPiggy(db, Piggy(
      id: piggyId,
      name: name,
      ownerAuthorId: myEmail,
      peerAuthorId: null,
      inviteCode: code,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await _subscribe(piggyId);
    await pullForPiggy(piggyId);
    piggyVersion.value++;
    return (PiggyCreateResult.success, code);
  }

  /// 用邀请码加入小金库：云端加入成功 → 本地 upsert + 订阅 + 拉取。
  Future<JoinPiggyResult> joinPiggy(String inviteCode) async {
    if (!_started && !await start()) return JoinPiggyResult.notReady;
    final supabase = SupabaseManager.instance;
    final Map<String, dynamic>? row;
    try {
      row = await supabase.joinPiggyByInvite(
        inviteCode.trim().toUpperCase(),
      );
    } on SocketException {
      // 网络层失败：断网/对端不可达，与邀请码本身无关，提示检查网络。
      return JoinPiggyResult.joinFailed;
    } on TimeoutException {
      return JoinPiggyResult.joinFailed;
    } catch (_) {
      // RPC 服务端异常（如 RLS 拒绝、函数报错）：也不应归咎于邀请码。
      return JoinPiggyResult.joinFailed;
    }
    if (row == null) return JoinPiggyResult.inviteInvalid;
    final piggyId = row['id']?.toString();
    if (piggyId == null || piggyId.isEmpty) return JoinPiggyResult.joinFailed;

    final db = await DatabaseHelper.instance.database;
    await _upsertPiggy(db, Piggy(
      id: piggyId,
      name: row['name']?.toString() ?? '小金库',
      ownerAuthorId: row['owner_email']?.toString(),
      peerAuthorId: row['peer_email']?.toString(),
      inviteCode: row['invite_code']?.toString() ??
          inviteCode.trim().toUpperCase(),
      createdAt: _parseEpochOrNull(row['created_at']) ??
          DateTime.now().millisecondsSinceEpoch,
    ));
    await _subscribe(piggyId);
    await pullForPiggy(piggyId);
    piggyVersion.value++;
    return JoinPiggyResult.success;
  }

  // ==================== 存取与记账联动 ====================

  /// 存入：云端事件确认（拿到 op_id）→ 本地 piggy 事件 → 记账联动。
  /// [linkedAccountId] 非空时联动个人资产账户（存=账户支出，余额减少）；
  /// 为空且 [recordToLedger] 时仅生成普通记录到当前账本（不调账户余额）；
  /// 都不满足时只记小金库，不产生 records。失败返回 false，不落任何本地。
  Future<bool> deposit({
    required String piggyId,
    required int amountCents,
    String remark = '',
    String? linkedAccountId,
    bool recordToLedger = false,
  }) {
    return _applyOp(
      piggyId: piggyId,
      op: 'deposit',
      amountCents: amountCents,
      remark: remark,
      linkedAccountId: linkedAccountId,
      recordToLedger: recordToLedger,
    );
  }

  /// 取出：语义同 [deposit]，方向相反（取=账户收入，余额增加）。
  Future<bool> withdraw({
    required String piggyId,
    required int amountCents,
    String remark = '',
    String? linkedAccountId,
    bool recordToLedger = false,
  }) {
    return _applyOp(
      piggyId: piggyId,
      op: 'withdraw',
      amountCents: amountCents,
      remark: remark,
      linkedAccountId: linkedAccountId,
      recordToLedger: recordToLedger,
    );
  }

  Future<bool> _applyOp({
    required String piggyId,
    required String op,
    required int amountCents,
    String remark = '',
    String? linkedAccountId,
    bool recordToLedger = false,
  }) async {
    if (amountCents <= 0 || !_started) return false;
    final supabase = SupabaseManager.instance;
    final myEmail = supabase.email;
    if (myEmail == null) return false;
    final delta = op == 'deposit' ? amountCents : -amountCents;

    // 1. 云端追加事件（幂等键 op_id）；失败返回 null 则不落本地、不提交。
    final opId = await supabase.appendPiggyOp(
      piggyId: piggyId,
      entityId: genId(),
      op: op,
      payload: {
        'piggy_id': piggyId,
        'delta': delta,
        'remark': remark,
        'operator_email': myEmail,
      },
      deviceId: _deviceId ?? await getOrCreateDeviceId(),
    );
    if (opId == null) return false;

    // 记录构造统一走现有 record 流程（author/author_id 补齐），
    // 关联账户的记录在事务内与账户余额/对账调整一起落库。
    final isDeposit = op == 'deposit';
    final linkedRecord = linkedAccountId != null
        ? await _buildPiggyRecord(
            isExpense: isDeposit,
            amountCents: amountCents,
            remark: remark,
            accountId: linkedAccountId,
          )
        : null;
    final plainRecord = (linkedAccountId == null && recordToLedger)
        ? await _buildPiggyRecord(
            isExpense: isDeposit,
            amountCents: amountCents,
            remark: remark,
            accountId: null,
          )
        : null;

    final db = await DatabaseHelper.instance.database;
    // 2. 本地小金库事件（op_id 幂等，防重复）。
    await db.insert(
      'piggy_events',
      {
        'op_id': opId,
        'piggy_id': piggyId,
        'op': op,
        'delta': delta,
        'remark': remark,
        'operator_email': myEmail,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // 3. 记账联动：统一复用 insertRecord——其内部已处理账户余额 ±、
    //    余额历史重算（notifyChanged）、版本通知与共享账本 enqueueRecord。
    //    不再手动写 balance_adjustments / UPDATE balance_cents，
    //    避免与 records 在快照重算时双重计负、资产曲线错乱。
    final rec = linkedRecord ?? plainRecord;
    if (rec != null) {
      await insertRecord(rec);
    }

    piggyVersion.value++;
    return true;
  }

  /// 构造小金库记账记录（category '小金库'，author 按现有流程补齐）。
  Future<Record> _buildPiggyRecord({
    required bool isExpense,
    required int amountCents,
    required String remark,
    required String? accountId,
  }) async {
    final now = DateTime.now();
    final nickname = await currentNickname();
    final authorId = await AuthorService.instance.ensureAuthorId();
    return Record(
      id: genId(),
      ledgerId: currentLedgerId.value,
      accountId: accountId,
      isExpense: isExpense,
      categoryName: '小金库',
      amountCents: amountCents,
      remark: remark,
      date: now,
      createdAt: now,
      author: nickname,
      authorId: authorId,
    );
  }

  // ==================== 余额与流水 ====================

  /// 某金库当前余额（本地事件代数和的镜像）。
  Future<int> balanceOf(String piggyId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(delta), 0) AS total FROM piggy_events '
      'WHERE piggy_id = ?',
      [piggyId],
    );
    return (rows.first['total'] as num).toInt();
  }

  /// 我参与的所有金库余额合计（正余额计入资产汇总）。
  Future<int> totalPiggyBalance() async {
    var total = 0;
    for (final p in await loadMyPiggies()) {
      final b = await balanceOf(p.id);
      if (b > 0) total += b;
    }
    return total;
  }

  /// 金库存取流水（按云端 op_id 倒序）。
  Future<List<PiggyEvent>> loadEvents(String piggyId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'piggy_events',
      where: 'piggy_id = ?',
      whereArgs: [piggyId],
      orderBy: 'op_id DESC',
    );
    return rows.map(PiggyEvent.fromDbMap).toList();
  }

  // ==================== 同步位点 ====================

  Future<int> _getCursor(String piggyId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: ['piggy_cursor:$piggyId'],
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String) ?? 0;
  }

  Future<void> _setCursor(String piggyId, int cursor) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'sync_state',
      {'key': 'piggy_cursor:$piggyId', 'value': '$cursor'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==================== 工具 ====================

  /// 6 位邀请码（与共享账本同风格，去除易混淆字符）。
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// 兼容解析时间戳：数字（毫秒）或 ISO 字符串直接返回；无法解析返回 null。
  static int? _parseEpochOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) {
      return DateTime.tryParse(v)?.millisecondsSinceEpoch;
    }
    return null;
  }
}