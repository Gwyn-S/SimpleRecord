import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/ledger.dart';
import '../models/record.dart';
import 'cloud_config.dart';
import 'database.dart';
import 'record_service.dart';
import 'settings.dart';
import 'supabase_service.dart';

/// 加入失败细分原因。
enum JoinSyncResult { notReady, roomNotFound, joinFailed, success }

/// 同步引擎：本地 SQLite <-> Supabase 的双向增量同步。
///
/// 模型：oplog 事务日志 + id 位点增量拉取 + Realtime 推送即时生效。
/// 上行写 [DatabaseHelper] 的 sync_outbox，flush 时推进云端 oplogs 并标记已推；
/// 下行按 sync_state 位点拉取，device_id 为本机则跳过（防回声）。
/// 冲突策略：最后写赢（同一实体按 created_at 整行替换）。
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  bool _started = false;
  bool _online = false;
  String? _deviceId;

  /// 邀请码本地缓存：避免每次打开编辑弹窗都联网查询。
  final Map<String, String> _inviteCodeCache = {};

  /// 数据有变化（含同步回来后）时自增，外层用 ValueListenableBuilder 刷新。
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  bool get isStarted => _started;
  bool get isOnline => _online;

  // ==================== 生命周期 ====================

  /// 启动：初始化 -> 匿名登录 -> 订阅实时通道 -> 先吐后拉。
  /// 未配置 Supabase 时静默返回 false，不阻塞 App 正常使用。
  Future<bool> start() async {
    if (_started) return true;
    await SupabaseManager.instance.init();
    if (!SupabaseManager.instance.isReady) return false;
    if (!await SupabaseManager.instance.ensureSignedIn()) return false;
    _deviceId = await getOrCreateDeviceId();
    _online = true;
    _started = true;
    await _subscribeRooms();
    await _resubscribeRoomsFromLocal();
    await flush();
    await pullAll();
    return true;
  }

  /// 回前台/手动刷新：先吐未推日志，再拉增量。
  Future<void> refresh() async {
    if (!_started) return;
    await flush();
    await pullAll();
  }

  /// 云配置更新后重建连接（仅供设置入口调用）。
  Future<bool> reconfigure() async {
    await SupabaseManager.instance.reconnect();
    _started = false;
    _online = false;
    return start();
  }

  // ==================== 上行：入队与推送 ====================

  /// 记录写入钩子：本地已落库后调用，把变更推进 outbox。
  /// [op] 取值 insert / update / delete。
  Future<void> enqueueRecord(Record record, {required String op}) async {
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

  /// 昵称变更广播：向所有共享账本发 profile 事件，对方收到后更新昵称映射。
  Future<void> enqueueProfileChange({
    required String authorId,
    required String nickname,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('books', where: 'sync_mode = 1');
    for (final row in rows) {
      final roomId = row['id'] as String;
      await _enqueue(
        entityType: 'profile',
        entityId: authorId,
        op: 'update',
        bookId: roomId,
        payload: {
          'author_id': authorId,
          'nickname': nickname,
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

  /// 把 outbox 里未推的日志推上云端，逐条成功即标记已推。
  Future<void> flush() async {
    if (!_online) return;
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('sync_outbox',
        where: 'state = 0', orderBy: 'id', limit: 200);
    if (rows.isEmpty) return;
    final supabase = SupabaseManager.instance;
    final deviceId = _deviceId ?? await getOrCreateDeviceId();
    final done = <int>[];
    for (final row in rows) {
      final ok = await supabase.appendOplog(
        roomId: row['book_id'] as String,
        entityType: row['entity_type'] as String,
        entityId: row['entity_id'] as String,
        op: row['op'] as String,
        payload: _decodePayload(row['payload'] as String),
        deviceId: deviceId,
      );
      if (ok != null) done.add(row['id'] as int);
    }
    if (done.isEmpty) return;
    final batch = db.batch();
    for (final id in done) {
      batch.update('sync_outbox', {'state': 1},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  // ==================== 下行：增量拉取与应用 ====================

  /// 拉取并应用所有共享账本的增量。
  Future<void> pullAll() async {
    if (!_online) return;
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('books', where: 'sync_mode = 1');
    for (final row in rows) {
      await pullForRoom(row['id'] as String);
    }
  }

  /// 拉取单个房间增量：循环翻页直到追平，末尾整体推进位点。
  /// 幂等设计：本地应用全部用整行替换/按 id 删除，重复拉取无副作用。
  Future<void> pullForRoom(String roomId) async {
    if (!_online) return;
    final supabase = SupabaseManager.instance;
    final db = await DatabaseHelper.instance.database;
    var cursor = await _getCursor(roomId);
    while (true) {
      final ops =
          await supabase.fetchOplogs(roomId, afterId: cursor, limit: 200);
      if (ops.isEmpty) break;
      var maxId = cursor;
      for (final op in ops) {
        final id = (op['id'] as num?)?.toInt() ?? 0;
        if (id > maxId) maxId = id;
        if (op['device_id'] == _deviceId) continue;
        await _applyRemoteOp(db, op);
      }
      await _setCursor(roomId, maxId);
      cursor = maxId;
      if (ops.length < 200) break;
    }
    version.value++;
    recordsVersion.value++;
  }

  /// 把一条远端 oplog 应用到本地（整行替换，幂等）。
  Future<void> _applyRemoteOp(Database db, Map<String, dynamic> op) async {
    final entityType = op['entity_type'] as String? ?? '';
    final entityId = op['entity_id'] as String? ?? '';
    final entityOp = op['op'] as String? ?? '';
    final payload =
        op['payload'] is Map ? Map<String, dynamic>.from(op['payload'] as Map) : null;
    if (payload == null) return;

    if (entityType == 'record') {
      payload
        ..remove('image_path')
        ..['account_id'] = null;
      switch (entityOp) {
        case 'insert':
        case 'update':
          await db.insert('records', payload,
              conflictAlgorithm: ConflictAlgorithm.replace);
        case 'delete':
          await db.delete('records',
              where: 'id = ?', whereArgs: [entityId]);
      }
    } else if (entityType == 'ledger') {
      switch (entityOp) {
        case 'insert':
          payload['sync_mode'] = 1;
          await db.insert('books', payload,
              conflictAlgorithm: ConflictAlgorithm.replace);
        case 'update':
          await db.update('books',
              {'name': payload['name'], 'sync_mode': 1},
              where: 'id = ?', whereArgs: [entityId]);
        case 'delete':
          await db.delete('records',
              where: 'book_id = ?', whereArgs: [entityId]);
          await db.delete('books', where: 'id = ?', whereArgs: [entityId]);
      }
    } else if (entityType == 'profile') {
      // 昵称变更：更新本地 author_id -> 昵称 映射并触发界面刷新。
      final authorId = payload['author_id'] as String?;
      final nickname = payload['nickname'] as String?;
      if (authorId != null && authorId.isNotEmpty && nickname != null) {
        await _setNicknameMapping(authorId, nickname);
      }
      version.value++;
      recordsVersion.value++;
    }
  }

  /// 记录 author_id -> 昵称 映射；与本地 author_id 同源关系由外部维护。
  Future<void> _setNicknameMapping(String authorId, String nickname) async {
    await Settings.setString('nickname_of_$authorId', nickname);
  }

  // ==================== 共享账本编排 ====================

  /// 确保就绪并登录。用于 UI 里的"开启共享/加入"入口。
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
      final code = await supabase.createRoom(
        roomId: ledger.id,
        name: ledger.name,
        inviteCode: invite,
      );
      ok = code != null;
      if (ok) invite = code;
    }
    if (!ok) return false;
    _inviteCodeCache[ledger.id] = invite;
    await _setSharedFlag(ledger.id, 1);
    await supabase.subscribeOplogs(
      roomId: ledger.id,
      callback: (payload) {
        final roomId = payload.newRecord['room_id']?.toString();
        if (roomId != null) pullForRoom(roomId);
      },
    );
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
    await flush();
    await pullForRoom(ledger.id);
    return true;
  }

  /// 关闭多人记账：清缓存并置本地 sync_mode 0（不再参与该房间同步）。
  Future<bool> disableSync(String bookId) async {
    _inviteCodeCache.remove(bookId);
    await _setSharedFlag(bookId, 0);
    return true;
  }

  /// 用邀请码加入共享账本：云端 room -> 本地建账本 -> 全量拉取。
  /// 返回 (结果, 本地账本)。
  Future<(JoinSyncResult, Ledger?)> joinByInvite(String code) async {
    if (!await ensureOnline()) return (JoinSyncResult.notReady, null);
    final supabase = SupabaseManager.instance;
    final room = await supabase.fetchRoomByInvite(code);
    if (room == null) return (JoinSyncResult.roomNotFound, null);
    final roomId = room['id'].toString();
    if (!await supabase.joinRoom(roomId)) {
      return (JoinSyncResult.joinFailed, null);
    }

    final db = await DatabaseHelper.instance.database;
    final existing = await db.query('books', where: 'id = ?', whereArgs: [roomId]);
    late final Ledger ledger;
    if (existing.isNotEmpty) {
      ledger = Ledger.fromDbMap(existing.first)..syncMode = 1;
      await db.update('books', {'sync_mode': 1}, where: 'id = ?', whereArgs: [roomId]);
    } else {
      ledger = Ledger(
        id: roomId,
        name: room['name'].toString(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        syncMode: 1,
      );
      await db.insert('books', ledger.toDbMap());
    }
    await supabase.subscribeOplogs(
      roomId: roomId,
      callback: (payload) {
        final id = payload.newRecord['room_id']?.toString();
        if (id != null) pullForRoom(id);
      },
    );
    final inviteCode = room['invite_code']?.toString();
    if (inviteCode != null && inviteCode.isNotEmpty) {
      _inviteCodeCache[roomId] = inviteCode;
    }
    await pullForRoom(roomId);
    version.value++;
    return (JoinSyncResult.success, ledger);
  }

  /// 按账本 id 取邀请码（UI 展示/复制用），非共享或失败返回 null。
  Future<String?> getInviteCode(String bookId) async {
    final cached = _inviteCodeCache[bookId];
    if (cached != null && cached.isNotEmpty) return cached;
    if (!_online) return null;
    final room = await SupabaseManager.instance.fetchRoom(bookId);
    final code = room?['invite_code']?.toString();
    if (code != null && code.isNotEmpty) _inviteCodeCache[bookId] = code;
    return (code == null || code.isEmpty) ? null : code;
  }

  /// 预取一批账本的邀请码到缓存，避免打开编辑弹窗时联网卡顿。
  Future<void> precacheInviteCodes(Iterable<String> bookIds) async {
    if (!_online) return;
    for (final id in bookIds) {
      if (_inviteCodeCache.containsKey(id)) continue;
      final room = await SupabaseManager.instance.fetchRoom(id);
      final code = room?['invite_code']?.toString();
      if (code != null && code.isNotEmpty) _inviteCodeCache[id] = code;
    }
  }

  // ==================== 本地辅助 ====================

  Future<bool> isSharedBook(String bookId) async {
    final db = await DatabaseHelper.instance.database;
    final rows =
        await db.query('books', columns: ['sync_mode'], where: 'id = ?', whereArgs: [bookId]);
    if (rows.isEmpty) return false;
    return rows.first['sync_mode'] == 1;
  }

  Future<void> _setSharedFlag(String bookId, int mode) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('books', {'sync_mode': mode}, where: 'id = ?', whereArgs: [bookId]);
  }

  Future<List<Record>> _loadRecords(String bookId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('records',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'created_at');
    return rows.map(Record.fromDbMap).toList();
  }

  Future<int> _getCursor(String roomId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('sync_state',
        where: 'key = ?', whereArgs: ['oplog_cursor:$roomId']);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String) ?? 0;
  }

  Future<void> _setCursor(String roomId, int cursor) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'sync_state',
      {'key': 'oplog_cursor:$roomId', 'value': '$cursor'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除共享账本时清理本机同步位点与实时订阅（账本记录已被 deleteLedger
  /// 删掉，云端删除 oplog 已由 enqueueLedger 入队，会随下次 flush 推送）。
  Future<void> removeSharedState(String bookId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('sync_state',
        where: 'key = ?', whereArgs: ['oplog_cursor:$bookId']);
    await SupabaseManager.instance.unsubscribeOplogs(bookId);
  }

  Future<void> _resubscribeRoomsFromLocal() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('books', where: 'sync_mode = 1');
    final supabase = SupabaseManager.instance;
    for (final row in rows) {
      final roomId = row['id'] as String;
      await supabase.subscribeOplogs(
        roomId: roomId,
        callback: (payload) {
          final id = payload.newRecord['room_id']?.toString();
          if (id != null) pullForRoom(id);
        },
      );
    }
  }

  Future<void> _subscribeRooms() async {
    final supabase = SupabaseManager.instance;
    await supabase.subscribeRooms(callback: (payload) async {
      final roomId = payload.newRecord['id']?.toString();
      if (roomId == null) return;
      // 房间元数据变化（改名/成员）落地本地 books.name
      final name = payload.newRecord['name']?.toString();
      final db = await DatabaseHelper.instance.database;
      if (name != null && name.isNotEmpty) {
        await db.update('books', {'name': name},
            where: 'id = ? AND sync_mode = 1', whereArgs: [roomId]);
        version.value++;
      }
    });
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  static Map<String, dynamic> _decodePayload(String raw) {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }
}