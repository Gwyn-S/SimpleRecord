import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/data/ledger.dart';
import '../../models/data/record.dart';
import '../core/author_service.dart';
import '../core/cloud_config.dart';
import '../core/database.dart';
import '../data/category_service.dart';
import '../data/record_service.dart';
import 'supabase_service.dart';
import 'vault_op_service.dart';

/// 加入失败细分原因。
enum JoinSyncResult { notReady, ledgerNotFound, joinFailed, success }

/// 同步引擎：本地 SQLite <-> Supabase 的双向增量同步。
///
/// 模型：ledgerOp 事务日志 + id 位点增量拉取 + Realtime 推送即时生效。
/// 上行写 [DatabaseHelper] 的 sync_outbox，flush 时推进云端 ledger_ops 并标记已推；
/// 下行按 sync_state 位点拉取，device_id 为本机则跳过（防回声）。
/// 冲突策略：最后写赢（同一实体按 created_at 整行替换）。
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  bool _started = false;
  bool _online = false;
  bool _flushing = false;
  bool _recheck = false;
  String? _deviceId;

  /// 邀请码本地缓存：避免每次打开编辑弹窗都联网查询。
  final Map<String, String> _inviteCodeCache = {};

  bool get isStarted => _started;
  bool get isOnline => _online;

  /// 是否已用真实邮箱账号登录（会话有效）。未登录时共享能力整体不可用。
  bool get isSignedIn => SupabaseManager.instance.email != null;

  // ==================== 生命周期 ====================

  /// 启动：初始化 -> 确认真实账号已登录 -> 订阅实时通道 -> 先吐后拉。
  /// 未配置 Supabase / 未登录（邮箱）时静默返回 false，不阻塞 App 正常使用。
  Future<bool> start() async {
    if (_started) return true;
    await SupabaseManager.instance.init();
    if (!SupabaseManager.instance.isReady) return false;
    if (!await SupabaseManager.instance.ensureSignedIn()) return false;
    _deviceId = await getOrCreateDeviceId();
    _online = true;
    _started = true;
    await _restoreMyLedgers();
    await _subscribeLedgers();
    await _resubscribeLedgersFromLocal();
    await flush();
    await VaultOpService.instance.flush();
    await pullAll();
    await _restoreRemoteProfiles();
    // 换设备/清数据后登录：把云端"我参与的"金库恢复回本地列表，
    // 再据此订阅并重放历史事件（余额/改名/备注一并重建）。
    await VaultOpService.instance.restoreMyVaults();
    // 金库下行：为本地全部小金库恢复订阅并追平，保证 B 端加入后能实时
    // 接收对方的存取事件、两台机最终一致。
    await VaultOpService.instance.resubscribeLocalVaults();
    return true;
  }

  /// 完全停止同步引擎：断开实时订阅、停推送并重置状态。
  /// 登出/切换账号时调用，避免残留 outbox 用已失效的会话继续推送。
  /// 注意：不清空 outbox——本地记录改动仍需保留，等重新登录后再由
  /// start() 的 flush() 推送，否则离线期间的改动会永久丢失。
  Future<void> stop() async {
    final supabase = SupabaseManager.instance;
    if (supabase.isReady) {
      await supabase.disposeChannels();
    }
    _started = false;
    _online = false;
  }

  // ==================== 上行：入队与推送 ====================

  /// 记录写入钩子：本地已落库后调用，把变更推进 outbox。
  /// [op] 取值 insert / update / delete。
  Future<void> enqueueRecord(Record record, {required String op}) async {
    if (record.authorId == null) return;
    final bookId = record.ledgerId;
    if (bookId == null) return;
    if (!await isSharedBook(bookId)) return;
    final payload = record.toDbMap()
      ..remove('image_path')
      ..['account_id'] = null;
    await _enqueue(
      entityType: 'record',
      entityId: record.id,
      op: op,
      bookId: bookId,
      payload: payload,
    );
    unawaited(flush());
  }

  /// 账本写入钩子：新建/改名/删除共享账本时调用。
  Future<void> enqueueLedger(Ledger ledger, {required String op}) async {
    if (op != 'delete' && !await isSharedBook(ledger.id)) return;
    await _enqueue(
      entityType: 'ledger',
      entityId: ledger.id,
      op: op,
      bookId: ledger.id,
      payload: {
        'id': ledger.id,
        'name': ledger.name,
        'created_at': ledger.createdAt,
      },
    );
    unawaited(flush());
  }

  /// 分类写入钩子：本地已落库后调用（共享账本）。[op] 为 insert/update/delete。
  /// 远端收到后按主键 (ledger_id, name, is_expense) 整行应用。
  Future<void> enqueueCategory(
    Map<String, dynamic> categoryMap, {
    required String op,
  }) async {
    final ledgerId = categoryMap['ledger_id'] as String?;
    if (ledgerId == null) return;
    if (!await isSharedBook(ledgerId)) return;
    final name = categoryMap['name'] as String? ?? '';
    final isExpense = (categoryMap['is_expense'] as int? ?? 0) == 1;
    await _enqueue(
      entityType: 'category',
      entityId: '$name|${isExpense ? 1 : 0}',
      op: op,
      bookId: ledgerId,
      payload: categoryMap,
    );
    unawaited(flush());
  }

  /// 远端分类变更回调；由使用方注册（category_service），用于刷新分类缓存。
  Future<void> Function()? onCategoryRemoteChanged;

  /// 昵称/头像变更广播：向所有共享账本发 profile 事件，对方收到后更新映射。
  Future<void> enqueueProfileChange({
    required String authorId,
    String? nickname,
    String? avatarUrl,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('books', where: 'sync_mode = 1');
    for (final row in rows) {
      final ledgerId = row['id'] as String;
      await _enqueue(
        entityType: 'profile',
        entityId: authorId,
        op: 'update',
        bookId: ledgerId,
        payload: {
          'author_id': authorId,
          'nickname': ?nickname,
          'avatar_url': ?avatarUrl,
        },
      );
    }
    unawaited(flush());
  }

  Future<void> _enqueue({
    required String entityType,
    required String entityId,
    required String op,
    required String bookId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('sync_outbox', {
      'entity_type': entityType,
      'entity_id': entityId,
      'op': op,
      'book_id': bookId,
      'payload': jsonEncode(payload),
      'device_id': _deviceId ?? await getOrCreateDeviceId(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'state': 0,
    });
  }

  /// 把 outbox 里未推的日志推上云端，推送成功后即删除（队列只留待发的）。
  ///
  /// 串行调度：任意时刻最多一个 flush 循环在跑（防并发重复），循环内
  /// 一路发到 outbox 清空（防批量入队漏发）。入队时新塞的日志会被
  /// 当前这一轮循环顺手搬走。
  Future<void> flush() async {
    if (!_online) return;
    if (_flushing) {
      // 已在跑：标记"结束后再扫一轮"，当前循环会顺手搬走新入队的。
      _recheck = true;
      return;
    }
    _flushing = true;
    try {
      // 串行循环：一路搬到 outbox 清空；期间有新入队则再扫一轮。
      while (await _flushBatch() || _takeRecheck()) {}
    } finally {
      _flushing = false;
    }
  }

  bool _takeRecheck() {
    if (!_recheck) return false;
    _recheck = false;
    return true;
  }

  /// 推送一批并删除已推行；返回是否应继续循环（有待发且本批有进展）。
  Future<bool> _flushBatch() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'sync_outbox',
      where: 'state = 0',
      orderBy: 'id',
      limit: 200,
    );
    if (rows.isEmpty) return false;
    final supabase = SupabaseManager.instance;
    final deviceId = _deviceId ?? await getOrCreateDeviceId();
    final done = <int>[];
    for (final row in rows) {
      // 途中被 stop()/登出打断则立即停止本轮推送，避免用失效会话写云端。
      if (!_online) break;
      final ok = await supabase.appendLedgerOp(
        ledgerId: row['book_id'] as String,
        entityType: row['entity_type'] as String,
        entityId: row['entity_id'] as String,
        op: row['op'] as String,
        payload: _decodePayload(row['payload'] as String),
        deviceId: deviceId,
      );
      if (ok != null) done.add(row['id'] as int);
    }
    if (done.isEmpty) return false; // 本批全失败，退回避免空转
    final batch = db.batch();
    for (final id in done) {
      // 已推送成功，删除该条，避免 outbox 无限堆积。
      batch.delete(
        'sync_outbox',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
    return true; // 本批有进展且可能还有更多，继续搬
  }

  // ==================== 下行：增量拉取与应用 ====================

  /// 拉取并应用所有共享账本的增量。
  Future<void> pullAll() async {
    if (!_online) return;
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('books', where: 'sync_mode = 1');
    for (final row in rows) {
      await pullForLedger(row['id'] as String);
    }
  }

  /// 拉取单个房间增量：循环翻页直到追平，末尾整体推进位点。
  /// 幂等设计：本地应用全部用整行替换/按 id 删除，重复拉取无副作用。
  Future<void> pullForLedger(String ledgerId) async {
    if (!_online) return;
    final supabase = SupabaseManager.instance;
    final db = await DatabaseHelper.instance.database;
    var cursor = await _getCursor(ledgerId);
    // 仅当本轮实际应用到远端变更时才广播版本号，避免空拉取引发全量重建。
    var appliedAny = false;
    while (true) {
      final ops = await supabase.fetchLedgerOps(
        ledgerId,
        afterId: cursor,
        limit: 200,
      );
      if (ops.isEmpty) break;
      var maxId = cursor;
      for (final op in ops) {
        final id = (op['id'] as num?)?.toInt() ?? 0;
        if (id > maxId) maxId = id;
        if (op['device_id'] == _deviceId) continue;
        await _applyRemoteOp(db, op);
        appliedAny = true;
      }
      await _setCursor(ledgerId, maxId);
      cursor = maxId;
      if (ops.length < 200) break;
    }
    if (appliedAny) recordsVersion.value++;
  }

  /// 收到 ledgerOp INSERT 回调：按房间拉取增量（三处订阅统一入口）。
  /// Realtime 虽已按 ledger_id 服务端过滤，这里保留 ledger_id 再判作兜底。
  Future<void> _onLedgerOpInsert(PostgresChangePayload payload) async {
    final ledgerId = payload.newRecord['ledger_id']?.toString();
    if (ledgerId != null) await pullForLedger(ledgerId);
  }

  /// 把一条远端 ledgerOp 应用到本地（整行替换，幂等）。
  Future<void> _applyRemoteOp(Database db, Map<String, dynamic> op) async {
    final entityType = op['entity_type'] as String? ?? '';
    final entityId = op['entity_id'] as String? ?? '';
    final entityOp = op['op'] as String? ?? '';
    final payload = op['payload'] is Map
        ? Map<String, dynamic>.from(op['payload'] as Map)
        : null;
    if (payload == null) return;

    if (entityType == 'record') {
      payload
        ..remove('image_path')
        ..['account_id'] = null;
      switch (entityOp) {
        case 'insert':
        case 'update':
          await db.insert(
            'records',
            payload,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          break;
        case 'delete':
          await db.delete('records', where: 'id = ?', whereArgs: [entityId]);
          break;
      }
    } else if (entityType == 'ledger') {
      switch (entityOp) {
        case 'insert':
          payload['sync_mode'] = 1;
          await db.insert(
            'books',
            payload,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          break;
        case 'update':
          await db.update(
            'books',
            {'name': payload['name'], 'sync_mode': 1},
            where: 'id = ?',
            whereArgs: [entityId],
          );
          break;
        case 'delete':
          await db.delete(
            'records',
            where: 'book_id = ?',
            whereArgs: [entityId],
          );
          await db.delete('books', where: 'id = ?', whereArgs: [entityId]);
          break;
      }
    } else if (entityType == 'category') {
      final ledgerId = payload['ledger_id'] as String?;
      if (ledgerId == null) return;
      final name = payload['name'] as String? ?? '';
      final isExpense = payload['is_expense'] == 1 ||
          payload['is_expense'] == '1' ||
          payload['is_expense'] == true;
      switch (entityOp) {
        case 'insert':
        case 'update':
          await db.insert(
            'categories',
            {
              'ledger_id': ledgerId,
              'name': name,
              'is_expense': isExpense ? 1 : 0,
              'icon_name': payload['icon_name'] as String? ?? '',
              'sort_order': payload['sort_order'] as int? ?? 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          break;
        case 'delete':
          await db.delete(
            'categories',
            where: 'ledger_id = ? AND name = ? AND is_expense = ?',
            whereArgs: [ledgerId, name, isExpense ? 1 : 0],
          );
          break;
      }
      final cb = onCategoryRemoteChanged;
      if (cb != null) await cb();
    } else if (entityType == 'profile') {
      // 昵称/头像变更：更新本地 author_id -> 值 映射并触发界面刷新。
      // 仅在 payload 显式携带某字段时才更新对应映射，缺席字段保持现状，
      // 避免"只改昵称"的广播误把对方头像当作清除。
      final authorId = payload['author_id'] as String?;
      if (authorId != null && authorId.isNotEmpty) {
        if (payload.containsKey('nickname')) {
          await _setNicknameMapping(authorId, payload['nickname'] as String?);
        }
        if (payload.containsKey('avatar_url')) {
          await _setAvatarMapping(authorId, payload['avatar_url'] as String?);
        }
      }
      recordsVersion.value++;
    }
  }

  /// 记录 author_id -> 昵称 映射；与本地 author_id 同源关系由外部维护。
  Future<void> _setNicknameMapping(String authorId, String? nickname) async {
    if (nickname == null || nickname.isEmpty) return;
    await AuthorService.instance.registerNickname(authorId, nickname);
  }

  /// 记录 author_id -> 头像 URL；传空/null 表示清除。
  Future<void> _setAvatarMapping(String authorId, String? url) async {
    await AuthorService.instance.registerAvatar(authorId, url);
  }

  /// 以云端 profiles 表为权威源，全量恢复所有成员昵称/头像到本地缓存。
  /// 解决新设备/清数据登录后：ledger_ops 历史事件缺失或未广播过资料时，
  /// 本地昵称头像始终为空的问题。仅在引擎启动时拉一次，随后的变更
  /// 仍由 profile 事件实时增量。
  Future<void> _restoreRemoteProfiles() async {
    final profiles = await SupabaseManager.instance.fetchAllProfiles();
    if (profiles.isEmpty) return;
    for (final p in profiles) {
      final authorId = p['author_id'] as String?;
      if (authorId == null || authorId.isEmpty) continue;
      final nickname = p['nickname'] as String?;
      final avatarUrl = p['avatar_url'] as String?;
      if (nickname != null && nickname.isNotEmpty) {
        await _setNicknameMapping(authorId, nickname);
      }
      await _setAvatarMapping(authorId, avatarUrl);
    }
    recordsVersion.value++;
  }

  // ==================== 共享账本编排 ====================

  /// 确保云端就绪并登录。用于 UI 里的"开启共享/加入"入口。
  Future<bool> ensureOnline() async {
    if (!_online && !await start()) return false;
    return true;
  }

  /// 把（新建或存量）账本开启云共享：
  /// 建房间（邀请码带重试）-> 标 sync_mode -> 订阅 -> 存量记录全量上行。
  Future<bool> enableSync(Ledger ledger) async {
    if (!await ensureOnline()) return false;
    final supabase = SupabaseManager.instance;
    var ok = false;
    var invite = '';
    for (var i = 0; i < 5 && !ok; i++) {
      invite = _generateInviteCode();
      final code = await supabase.createLedger(
        ledgerId: ledger.id,
        name: ledger.name,
        inviteCode: invite,
      );
      ok = code != null;
      if (ok) invite = code;
    }
    if (!ok) return false;
    _inviteCodeCache[ledger.id] = invite;
    await _setSharedFlag(ledger.id, 1);
    // 归属当前登录账号：换号后该账本只对当前账号显示。
    final ownerId = await AuthorService.instance.existingAuthorId();
    if (ownerId != null) {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'books',
        {'owner_author_id': ownerId},
        where: 'id = ?',
        whereArgs: [ledger.id],
      );
    }
    await supabase.subscribeLedgerOps(ledgerId: ledger.id, callback: _onLedgerOpInsert);
    final records = await _loadRecords(ledger.id);
    for (final r in records) {
      final bookId = r.ledgerId;
      if (bookId == null) continue;
      final payload = r.toDbMap()
        ..remove('image_path')
        ..['account_id'] = null;
      await _enqueue(
        entityType: 'record',
        entityId: r.id,
        op: 'insert',
        bookId: bookId,
        payload: payload,
      );
    }
    final categories = await _loadCategories(ledger.id);
    for (final c in categories) {
      await _enqueue(
        entityType: 'category',
        entityId: '${c['name']}|${(c['is_expense'] as int) == 1 ? 1 : 0}',
        op: 'insert',
        bookId: ledger.id,
        payload: c,
      );
    }
    await flush();
    await pullForLedger(ledger.id);
    return true;
  }

  /// 关闭多人记账：清缓存并置本地 sync_mode 0（不再参与该房间同步）。
  Future<bool> disableSync(String bookId) async {
    _inviteCodeCache.remove(bookId);
    await _setSharedFlag(bookId, 0);
    return true;
  }

  /// 用邀请码加入共享账本：云端 ledger -> 本地建账本 -> 全量拉取。
  /// 返回 (结果, 本地账本)。
  Future<(JoinSyncResult, Ledger?)> joinByInvite(String code) async {
    if (!await ensureOnline()) return (JoinSyncResult.notReady, null);
    final supabase = SupabaseManager.instance;
    final Map<String, dynamic>? remote;
    try {
      remote = await supabase.joinLedgerByInvite(code);
    } on SocketException {
      // 网络层失败：断网/对端不可达，与邀请码本身无关，提示检查网络。
      return (JoinSyncResult.joinFailed, null);
    } on TimeoutException {
      // 请求超时：网络差或服务器慢，同样不是邀请码问题。
      return (JoinSyncResult.joinFailed, null);
    } catch (_) {
      // RPC 服务端异常（如 RLS 拒绝、函数报错）：也不应归咎于邀请码。
      return (JoinSyncResult.joinFailed, null);
    }
    if (remote == null) return (JoinSyncResult.ledgerNotFound, null);
    final ledgerId = remote['id'].toString();

    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'books',
      where: 'id = ?',
      whereArgs: [ledgerId],
    );
    // 加入即归属当前登录账号，换号后该账本只对当前账号显示。
    final ownerId = await AuthorService.instance.existingAuthorId();
    late final Ledger ledger;
    if (existing.isNotEmpty) {
      ledger = Ledger.fromDbMap(existing.first)..syncMode = 1;
      await db.update(
        'books',
        {
          'sync_mode': 1,
          'owner_author_id': ownerId,
        },
        where: 'id = ?',
        whereArgs: [ledgerId],
      );
    } else {
      ledger = Ledger(
        id: ledgerId,
        name: remote['name'].toString(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        syncMode: 1,
        ownerAuthorId: ownerId,
      );
      await db.insert('books', ledger.toDbMap());
    }
    await supabase.subscribeLedgerOps(ledgerId: ledgerId, callback: _onLedgerOpInsert);
    final inviteCode = remote['invite_code']?.toString();
    if (inviteCode != null && inviteCode.isNotEmpty) {
      _inviteCodeCache[ledgerId] = inviteCode;
    }
    await pullForLedger(ledgerId);
    // 拉取后分类为空（账本尚无分类记录，如老账本/功能上线前创建）时，
    // 用默认分类兜底，保证新加入成员也有可用分类。
    if (await _hasNoCategories(ledgerId)) {
      await seedCategoriesForLedger(ledgerId);
    }
    return (JoinSyncResult.success, ledger);
  }

  /// 按账本 id 取邀请码（UI 展示/复制用），非共享或失败返回 null。
  Future<String?> getInviteCode(String bookId) async {
    final cached = _inviteCodeCache[bookId];
    if (cached != null && cached.isNotEmpty) return cached;
    if (!_online) return null;
    final ledger = await SupabaseManager.instance.fetchLedger(bookId);
    final code = ledger?['invite_code']?.toString();
    if (code != null && code.isNotEmpty) _inviteCodeCache[bookId] = code;
    return (code == null || code.isEmpty) ? null : code;
  }

  /// 预取一批账本的邀请码到缓存，避免打开编辑弹窗时联网卡顿。
  Future<void> precacheInviteCodes(Iterable<String> bookIds) async {
    if (!_online) return;
    for (final id in bookIds) {
      if (_inviteCodeCache.containsKey(id)) continue;
      final ledger = await SupabaseManager.instance.fetchLedger(id);
      final code = ledger?['invite_code']?.toString();
      if (code != null && code.isNotEmpty) _inviteCodeCache[id] = code;
    }
  }

  // ==================== 本地辅助 ====================

  /// 判断账本是否为共享账本（本地 sync_mode=1）。
  Future<bool> isSharedBook(String bookId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'books',
      columns: ['sync_mode'],
      where: 'id = ?',
      whereArgs: [bookId],
    );
    if (rows.isEmpty) return false;
    return rows.first['sync_mode'] == 1;
  }

  Future<void> _setSharedFlag(String bookId, int mode) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'books',
      {'sync_mode': mode},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<Record>> _loadRecords(String bookId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'records',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at',
    );
    return rows.map(Record.fromDbMap).toList();
  }

  Future<List<Map<String, dynamic>>> _loadCategories(String bookId) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'categories',
      where: 'ledger_id = ?',
      whereArgs: [bookId],
      orderBy: 'sort_order',
    );
  }

  Future<bool> _hasNoCategories(String bookId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'categories',
      columns: ['name'],
      where: 'ledger_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isEmpty;
  }

  Future<int> _getCursor(String ledgerId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: ['ledger_ops_cursor:$ledgerId'],
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String) ?? 0;
  }

  Future<void> _setCursor(String ledgerId, int cursor) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('sync_state', {
      'key': 'ledger_ops_cursor:$ledgerId',
      'value': '$cursor',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 删除共享账本时清理本机同步位点与实时订阅（账本记录已被 deleteLedger
  /// 删掉，云端删除 ledgerOp 已由 enqueueLedger 入队，会随下次 flush 推送）。
  Future<void> removeSharedState(String bookId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'sync_state',
      where: 'key = ?',
      whereArgs: ['ledger_ops_cursor:$bookId'],
    );
    await SupabaseManager.instance.unsubscribeLedgerOps(bookId);
  }

  Future<void> _resubscribeLedgersFromLocal() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('books', where: 'sync_mode = 1');
    final supabase = SupabaseManager.instance;
    for (final row in rows) {
      final ledgerId = row['id'] as String;
      await supabase.subscribeLedgerOps(ledgerId: ledgerId, callback: _onLedgerOpInsert);
    }
  }

  /// 以云端 ledgers 表为准恢复"我加入过的共享账本"到本地。
  /// 换新设备/清数据后登录时，本地 books 为空，此前只能靠邀请码重新加入；
  /// 这里直接拉取当前账号（邮箱）所属的全部房间，落库 + 缓存邀请码，
  /// 使脱离本地的账本也能在登录后自动回来。拉取失败静默容忍。
  /// 已存在的账本仅同步名字，不覆盖 sync_mode(用户可已关闭共享) 与归属，
  /// 尊重用户本地的主动选择；只有本地缺失(换设备/清数据)才新建。
  /// 兼容解析时间戳：数字（毫秒）或 ISO 字符串直接返回；无法解析返回 null。
  static int? _parseEpochOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) {
      return DateTime.tryParse(v)?.millisecondsSinceEpoch;
    }
    return null;
  }

  Future<void> _restoreMyLedgers() async {
    final supabase = SupabaseManager.instance;
    final myEmail = supabase.email;
    if (myEmail == null || myEmail.isEmpty) return;
    final ledgers = await supabase.fetchMyLedgers();
    if (ledgers.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    for (final ledger in ledgers) {
      final ledgerId = ledger['id']?.toString();
      if (ledgerId == null || ledgerId.isEmpty) continue;
      final name = ledger['name']?.toString();
      final createdAt = _parseEpochOrNull(ledger['created_at']);
      final inviteCode = ledger['invite_code']?.toString();
      final existing = await db.query(
        'books',
        where: 'id = ?',
        whereArgs: [ledgerId],
      );
      if (existing.isNotEmpty) {
        // 本地已存在该账本（含用户主动关闭共享/仅本地保留的），
        // 仅同步名字，不覆盖 sync_mode 与归属，尊重用户本地的主动选择。
        if (name != null && name.isNotEmpty) {
          await db.update(
            'books',
            {'name': name},
            where: 'id = ?',
            whereArgs: [ledgerId],
          );
        }
      } else {
        final ledger = Ledger(
          id: ledgerId,
          name: name ?? '共享账本',
          createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
          syncMode: 1,
          ownerAuthorId: myEmail,
        );
        await db.insert('books', ledger.toDbMap());
      }
      if (inviteCode != null && inviteCode.isNotEmpty) {
        _inviteCodeCache[ledgerId] = inviteCode;
      }
      await supabase.subscribeLedgerOps(ledgerId: ledgerId, callback: _onLedgerOpInsert);
    }
    recordsVersion.value++;
  }

  Future<void> _subscribeLedgers() async {
    final supabase = SupabaseManager.instance;
    await supabase.subscribeLedgers(
      callback: (payload) async {
        final ledgerId = payload.newRecord['id']?.toString();
        if (ledgerId == null) return;
        // 房间元数据变化（改名/成员）落地本地 books.name
        final name = payload.newRecord['name']?.toString();
        final db = await DatabaseHelper.instance.database;
        if (name != null && name.isNotEmpty) {
          await db.update(
            'books',
            {'name': name},
            where: 'id = ? AND sync_mode = 1',
            whereArgs: [ledgerId],
          );
        }
      },
    );
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  static Map<String, dynamic> _decodePayload(String raw) {
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }
}
