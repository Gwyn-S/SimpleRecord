import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/data/asset_account.dart';
import '../../models/data/transfer.dart';
import '../../utils/formatters.dart';
import '../../utils/log.dart';
import '../core/author_service.dart';
import '../core/database.dart';
import '../core/cloud_config.dart';
import '../data/asset_account_service.dart';
import '../data/balance_history_service.dart';
import '../data/transfer_service.dart';
import 'supabase_service.dart';

/// 小金库云端事件推送（outbox 模式）。
///
/// 口径：金库参与的本地记账（转账、调整余额）以本地为准（先落本地再推云端）。
/// 本地落账后把事件写入 outbox，后台 [flush] 重试推送云端，成功后删除；
/// 断网/云端失败只延迟推送、不丢事件，策略上保证最终一致。
class VaultOpService {
  VaultOpService._();
  static final VaultOpService instance = VaultOpService._();

  bool _flushing = false;
  bool _recheck = false;

  /// 判断账户是否为多人金库（小金库分类即视为多人金库）。
  bool isSharedVault(AssetAccount? account) =>
      account != null && account.categoryName == '小金库';

  /// 转账落库后入队：金库作为转出方记 withdraw、转入方记 deposit；
  /// 删除转账则记 delete 事件。涉及两端的金库各入一条。
  Future<void> pushTransfer(Transfer t, {String op = 'insert'}) async {
    final accounts = await _loadAccounts();
    final byId = {for (final a in accounts) a.id: a};

    final fromVault = isSharedVault(byId[t.fromAccountId]);
    final toVault = isSharedVault(byId[t.toAccountId]);
    if (!fromVault && !toVault) return;

    final payloadBase = {
      'transfer_id': t.id,
      'amount_cents': t.amountCents,
      'fee_cents': t.feeCents,
      'remark': t.remark,
      'date': t.date.millisecondsSinceEpoch,
      'created_at': t.createdAt.millisecondsSinceEpoch,
      'from_account_id': t.fromAccountId,
      'to_account_id': t.toAccountId,
      'operator_email': t.operatorEmail.isNotEmpty
          ? t.operatorEmail
          : SupabaseManager.instance.email,
      'operator_nickname': t.operatorNickname.isNotEmpty
          ? t.operatorNickname
          : await AuthorService.instance.ownNickname() ?? '',
      'operator_avatar_url': (t.operatorAvatarUrl?.isNotEmpty ?? false)
          ? t.operatorAvatarUrl
          : await AuthorService.instance.ownAvatar() ?? '',
    };

    if (fromVault) {
      await _enqueue(
        vaultId: t.fromAccountId,
        entityId: op == 'delete'
            ? '${t.id}-from-del'
            : '${t.id}-from',
        op: op == 'delete' ? 'delete' : 'withdraw',
        payload: payloadBase,
      );
    }
    if (toVault) {
      await _enqueue(
        vaultId: t.toAccountId,
        entityId: op == 'delete'
            ? '${t.id}-to-del'
            : '${t.id}-to',
        op: op == 'delete' ? 'delete' : 'deposit',
        payload: payloadBase,
      );
    }
    unawaited(flush());
  }

  /// 手动调整余额后入队：金库余额按 delta 记 adjust。
  /// [entityId] 由调用方传入（= 本地 applyManualAdjustment 的 sourceId），
  /// 保证本机重放自己事件时幂等去重；缺省时内部生成。
  Future<void> pushAdjust({
    required String accountId,
    required int deltaCents,
    required int beforeCents,
    required int afterCents,
    String? entityId,
  }) async {
    final accounts = await _loadAccounts();
    final byId = {for (final a in accounts) a.id: a};
    if (!isSharedVault(byId[accountId])) return;

    await _enqueue(
      vaultId: accountId,
      entityId:
          entityId ?? '$accountId-adj-${DateTime.now().microsecondsSinceEpoch}',
      op: 'adjust',
      payload: {
        'delta_cents': deltaCents,
        'before_cents': beforeCents,
        'after_cents': afterCents,
        'date': toEpochDay(DateTime.now()),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'operator_email': SupabaseManager.instance.email,
      },
    );
    unawaited(flush());
  }

  /// 新建金库落库后入队：把初始余额通告给对端，B 端加入时据此重建。
  /// 复用 adjust 语义：before=0、after=初始余额。
  Future<void> pushInitialBalance(AssetAccount account) async {
    if (!isSharedVault(account)) return;
    await _enqueue(
      vaultId: account.id,
      entityId: '$account.id-init-${DateTime.now().microsecondsSinceEpoch}',
      op: 'adjust',
      payload: {
        'delta_cents': account.balanceCents,
        'before_cents': 0,
        'after_cents': account.balanceCents,
        'date': toEpochDay(DateTime.now()),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'operator_email': SupabaseManager.instance.email,
      },
    );
    unawaited(flush());
  }

  /// 普通记账落库后入队：记账把金库余额改变了 Δ（收入 +、支出 -），
  /// 等价于一次余额调整，以 adjust 语义通告对端（不传流水明细，只传数值+时间）。
  /// [before]/[after]/[date]/[createdAt] 由调用方从记账终态读出。
  /// [entityId] 由调用方传入（= 本地已写的调整记录 sourceId），保证幂等一致。
  Future<void> pushRecordDelta({
    required String accountId,
    required int deltaCents,
    required int beforeCents,
    required int afterCents,
    required int date,
    required int createdAt,
    required String? entityIdSuffix,
    String? entityId,
  }) async {
    final accounts = await _loadAccounts();
    final byId = {for (final a in accounts) a.id: a};
    if (!isSharedVault(byId[accountId])) return;

    await _enqueue(
      vaultId: accountId,
      entityId:
          entityId ?? '$accountId-rec-${DateTime.now().microsecondsSinceEpoch}-${entityIdSuffix ?? ''}',
      op: 'adjust',
      payload: {
        'delta_cents': deltaCents,
        'before_cents': beforeCents,
        'after_cents': afterCents,
        'date': date,
        'created_at': createdAt,
        'operator_email': SupabaseManager.instance.email,
      },
    );
    unawaited(flush());
  }

  Future<List<AssetAccount>> _loadAccounts() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('asset_accounts');
    return rows.map(AssetAccount.fromDbMap).toList();
  }

  /// 本地落库后入队（幂等：同 (vault_id, entity_id) 只留一条）。
  Future<void> _enqueue({
    required String vaultId,
    required String entityId,
    required String op,
    required Map<String, dynamic> payload,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final existed = await db.query(
      'vault_outbox',
      where: 'vault_id = ? AND entity_id = ?',
      whereArgs: [vaultId, entityId],
    );
    if (existed.isNotEmpty) return;
    await db.insert('vault_outbox', {
      'vault_id': vaultId,
      'entity_id': entityId,
      'op': op,
      'payload': jsonEncode(payload),
      'device_id': await getOrCreateDeviceId(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 把 outbox 里未推的日志推上云端，成功后删除（队列只留待发的）。
  /// 串行调度：任意时刻最多一个 flush 循环，循环内一路发到清空。
  Future<void> flush() async {
    final supabase = SupabaseManager.instance;
    if (supabase.isReady == false || supabase.uid == null) return;
    if (_flushing) {
      _recheck = true;
      return;
    }
    _flushing = true;
    try {
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

  /// 推送一批并删除已推的记录；返回是否应继续循环。
  Future<bool> _flushBatch() async {
    final db = await DatabaseHelper.instance.database;
    final supabase = SupabaseManager.instance;
    if (supabase.isReady == false || supabase.uid == null) return false;
    final rows = await db.query(
      'vault_outbox',
      orderBy: 'id',
      limit: 200,
    );
    if (rows.isEmpty) return false;
    final deviceId = await getOrCreateDeviceId();
    final done = <int>[];
    for (final row in rows) {
      if (supabase.uid == null) break;
      final ok = await supabase.appendVaultOp(
        vaultId: row['vault_id'] as String,
        entityId: row['entity_id'] as String,
        op: row['op'] as String,
        payload: _decodePayload(row['payload'] as String),
        deviceId: deviceId,
      );
      if (ok != null) done.add(row['id'] as int);
    }
    if (done.isEmpty) return false;
    final batch = db.batch();
    for (final id in done) {
      batch.delete('vault_outbox', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    return true;
  }

  static Map<String, dynamic> _decodePayload(String raw) {
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  // ==================== 下行：加入金库 + 增量重建 ====================
  //
  // B 端视角：本地没有 A 端的远端账户，只有金库账户本身。
  // 云端的 vault_ops 事件（withdraw/deposit/delete/adjust）里 payload 已带
  // 两端账户 id 与名称快照，B 端据此重建转账记录与金库余额。

  /// 用邀请码加入金库：云端 RPC 校验 → 本地落库金库账户 → 全量拉历史重建 → 订阅实时。
  /// 本地已存在同 id 金库（重复加入/换机恢复）则跳过落库、直接同步。
  /// 返回错误文案；成功返回 null。
  Future<String?> joinVaultByInvite(String inviteCode) async {
    final supabase = SupabaseManager.instance;
    if (!await supabase.ensureSignedIn()) return '请先登录账号';
    Map<String, dynamic>? vault;
    try {
      vault = await supabase.joinVaultByInvite(inviteCode);
    } catch (e) {
      appLog('[vault] joinVaultByInvite failed: $e');
      return '加入失败，请检查网络后重试';
    }
    if (vault == null) return '邀请码无效或该金库已满员';

    final vaultId = vault['id']?.toString();
    if (vaultId == null || vaultId.isEmpty) return '加入失败：缺少金库信息';

    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'asset_accounts',
      where: 'id = ?',
      whereArgs: [vaultId],
    );
    if (existing.isEmpty) {
      await insertAssetAccount(
        AssetAccount(
          id: vaultId,
          categoryName: '小金库',
          name: (vault['name'] as String?)?.isNotEmpty == true
              ? vault['name'] as String
              : '小金库',
          iconPath: 'assets/icons/vault_manage.svg',
          inviteCode: inviteCode.trim().toUpperCase(),
        ),
      );
    } else {
      final acc = AssetAccount.fromDbMap(existing.first);
      if (acc.inviteCode.isEmpty) {
        await db.update(
          'asset_accounts',
          {'invite_code': inviteCode.trim().toUpperCase()},
          where: 'id = ?',
          whereArgs: [vaultId],
        );
      }
    }

    await syncVaultOps(vaultId);
    await _subscribeVaultOps(vaultId);
    assetAccountsVersion.value++;
    transfersVersion.value++;
    return null;
  }

  /// 从云端增量拉取该金库的 vault_ops 并重建到本地。
  /// 幂等：转账按 id 幂等，重复拉取无副作用。
  Future<void> syncVaultOps(String vaultId) async {
    final supabase = SupabaseManager.instance;
    if (supabase.isReady == false || supabase.uid == null) return;
    final db = await DatabaseHelper.instance.database;
    var cursor = await _getVaultCursor(db, vaultId);
    var appliedAny = false;
    while (true) {
      final ops = await supabase.fetchVaultOps(vaultId, afterId: cursor);
      if (ops.isEmpty) break;
      var maxId = cursor;
      for (final op in ops) {
        final id = op['id'];
        final opId = id is int ? id : int.tryParse(id?.toString() ?? '');
        if (opId == null) continue;
        if (opId > maxId) maxId = opId;
        await _applyRemoteOp(db, vaultId, op);
        appliedAny = true;
      }
      await _setVaultCursor(db, vaultId, maxId);
      cursor = maxId;
      if (ops.length < 200) break;
    }
    if (appliedAny) {
      assetAccountsVersion.value++;
      transfersVersion.value++;
    }
  }

  /// 昵称/头像变更广播：向本地全部小金库各入队一条 profile 事件，
  /// 对方收到后更新 author_id -> 昵称/头像 映射（与共享账本广播同语义）。
  /// [nickname]/[avatarUrl] 传 null 表示本次不改该项（缺席字段不更新）。
  Future<void> enqueueProfileChange({
    required String authorId,
    String? nickname,
    String? avatarUrl,
  }) async {
    final accounts = await _loadAccounts();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    for (final a in accounts) {
      if (!isSharedVault(a)) continue;
      await _enqueue(
        vaultId: a.id,
        entityId: 'profile-$authorId-$stamp',
        op: 'profile',
        payload: {
          'author_id': authorId,
          'nickname': ?nickname,
          'avatar_url': ?avatarUrl,
        },
      );
    }
    unawaited(flush());
  }

  /// 金库资料变更广播：改名/改备注（图标不可编辑、不在此列）。
  /// 缺席字段不更新，对端与新设备（恢复列表后重放事件）据此同步。
  Future<void> pushVaultProfile({
    required String accountId,
    String? name,
    String? remark,
  }) async {
    final accounts = await _loadAccounts();
    final byId = {for (final a in accounts) a.id: a};
    if (!isSharedVault(byId[accountId])) return;
    await _enqueue(
      vaultId: accountId,
      entityId: '$accountId-vault-$name-$remark-${DateTime.now().microsecondsSinceEpoch}',
      op: 'profile',
      payload: {
        'author_id': SupabaseManager.instance.email ?? '',
        'vault_name': ?name,
        'vault_remark': ?remark,
      },
    );
    unawaited(flush());
  }

  /// 把一条远端 vaultOp 应用到本地（整行替换/按 id 删除，幂等）。
  Future<void> _applyRemoteOp(
    Database db,
    String vaultId,
    Map<String, dynamic> op,
  ) async {
    final action = op['op'] as String? ?? '';
    final payload = op['payload'];
    if (payload is! Map) return;
    final p = Map<String, dynamic>.from(payload);

    switch (action) {
      case 'profile':
        // 成员资料变更：更新 author_id 映射（缺席字段不更新）。
        final authorId = p['author_id']?.toString() ?? '';
        if (authorId.isNotEmpty) {
          if (p.containsKey('nickname')) {
            final n = p['nickname']?.toString();
            if (n != null && n.isNotEmpty) {
              await AuthorService.instance.registerNickname(authorId, n);
            }
          }
          if (p.containsKey('avatar_url')) {
            await AuthorService.instance.registerAvatar(
              authorId,
              p['avatar_url']?.toString(),
            );
          }
        }
        // 金库资料变更：改名/改备注（缺席字段不更新；自己 push 的不覆盖，
        // 因为本地已是最新，直接应用对本地也幂等无害）。
        final name = p['vault_name']?.toString();
        final remark = p['vault_remark']?.toString();
        if (name != null || remark != null) {
          final updates = <String, dynamic>{};
          if (name != null && name.isNotEmpty) updates['name'] = name;
          if (remark != null) updates['remark'] = remark;
          if (updates.isNotEmpty) {
            await db.update(
              'asset_accounts',
              updates,
              where: 'id = ?',
              whereArgs: [vaultId],
            );
            assetAccountsVersion.value++;
          }
        }
        break;
      case 'withdraw':
      case 'deposit':
        await _replayTransfer(db, p);
        break;
      case 'delete':
        final transferId = p['transfer_id']?.toString();
        if (transferId != null && transferId.isNotEmpty) {
          final rows = await db.query(
            'transfers',
            where: 'id = ?',
            whereArgs: [transferId],
          );
          if (rows.isNotEmpty) {
            await deleteTransfer(transferId);
          }
        }
        break;
      case 'adjust':
        final after = (p['after_cents'] as num?)?.toInt();
        final delta = (p['delta_cents'] as num?)?.toInt();
        final before = (p['before_cents'] as num?)?.toInt();
        if (after == null || delta == null || before == null) return;
        await db.update(
          'asset_accounts',
          {'balance_cents': after},
          where: 'id = ?',
          whereArgs: [vaultId],
        );
        // 对端/重放端统一靠 source_id 幂等：本机自己 push 的事件
        // 与本地已写记录同源会被跳过；换设备重放因无同源记录正常写入。
        await BalanceHistoryService.instance.recordAdjustment(
          accountId: vaultId,
          date: (p['date'] as num?)?.toInt() ?? toEpochDay(DateTime.now()),
          deltaCents: delta,
          beforeCents: before,
          afterCents: after,
          createdAt: (p['created_at'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
          sourceId: op['entity_id']?.toString() ?? '',
        );
        break;
    }
  }

  /// 远端转账事件重建本地记录：用 payload 里的两端账户 ID 与时间重建。
  /// 对端账户（非金库）在 B 端可能不存在，ID 照常写入，金额/时间原样还原。
  Future<void> _replayTransfer(Database db, Map<String, dynamic> p) async {
    final transferId = p['transfer_id']?.toString();
    if (transferId == null || transferId.isEmpty) return;
    final rows = await db.query(
      'transfers',
      where: 'id = ?',
      whereArgs: [transferId],
    );
    if (rows.isNotEmpty) return;

    final amountCents = (p['amount_cents'] as num?)?.toInt() ?? 0;
    final feeCents = (p['fee_cents'] as num?)?.toInt() ?? 0;
    final dateMs = (p['date'] as num?)?.toInt() ?? 0;
    final createdAtMs = (p['created_at'] as num?)?.toInt() ?? 0;
    final fromId = p['from_account_id']?.toString() ?? '';
    final toId = p['to_account_id']?.toString() ?? '';
    final opEmail = p['operator_email']?.toString() ?? '';

    // 由对端重建转账：余额更新用本地事务的 _applyTransfer 语义（插入流水后
    // 相应加减两端账户余额）。本地端账户若是由此事件引入的金库账户会在之前
    // 落库；对端账户不存在时 update 影响 0 行，不影响金库侧余额。
    await db.transaction((txn) async {
      await txn.insert('transfers', {
        'id': transferId,
        'from_account_id': fromId,
        'to_account_id': toId,
        'amount_cents': amountCents,
        'fee_cents': feeCents,
        'remark': p['remark']?.toString() ?? '',
        'date': toEpochDay(DateTime.fromMillisecondsSinceEpoch(dateMs)),
        'created_at': createdAtMs,
        'operator_email': opEmail,
        'operator_nickname': p['operator_nickname']?.toString() ?? '',
        'operator_avatar_url': p['operator_avatar_url']?.toString() ?? '',
      });
      await txn.rawUpdate(
        'UPDATE asset_accounts SET balance_cents = balance_cents - ? WHERE id = ?',
        [amountCents + feeCents, fromId],
      );
      await txn.rawUpdate(
        'UPDATE asset_accounts SET balance_cents = balance_cents + ? WHERE id = ?',
        [amountCents, toId],
      );
    });
  }

  /// 订阅该金库的实时事件：对方写入 vault_ops 立即触发增量重建。
  Future<void> _subscribeVaultOps(String vaultId) async {
    final supabase = SupabaseManager.instance;
    if (supabase.isReady == false) return;
    await supabase.subscribeVaultOps(vaultId: vaultId, callback: (_) {
      unawaited(syncVaultOps(vaultId));
    });
  }

  /// 换设备/清数据后登录：把云端"我参与"的金库恢复回本地列表。
  /// 名字以云端为权威；随后 resubscribeLocalVaults 全量重放事件
  /// 重建余额与改名/备注。本地已存在同 id 金库仅更新名字。
  Future<void> restoreMyVaults() async {
    final supabase = SupabaseManager.instance;
    if (!supabase.isReady) return;
    final vaults = await supabase.fetchMyVaults();
    if (vaults.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    for (final vault in vaults) {
      final vaultId = vault['id']?.toString();
      if (vaultId == null || vaultId.isEmpty) continue;
      final name = vault['name']?.toString();
      final inviteCode = vault['invite_code']?.toString();
      final existing = await db.query(
        'asset_accounts',
        where: 'id = ?',
        whereArgs: [vaultId],
      );
      if (existing.isEmpty) {
        await insertAssetAccount(
          AssetAccount(
            id: vaultId,
            categoryName: '小金库',
            name: (name?.isNotEmpty ?? false) ? name! : '小金库',
            iconPath: 'assets/icons/vault_manage.svg',
            inviteCode: inviteCode ?? '',
          ),
        );
      } else if (name?.isNotEmpty ?? false) {
        await db.update(
          'asset_accounts',
          {'name': name},
          where: 'id = ?',
          whereArgs: [vaultId],
        );
      }
    }
    assetAccountsVersion.value++;
  }

  /// 登录后调用：为本地全部金库恢复订阅并追平到最新。
  Future<void> resubscribeLocalVaults() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'asset_accounts',
      where: 'category_name = ?',
      whereArgs: ['小金库'],
    );
    for (final row in rows) {
      final vaultId = row['id'] as String;
      await _subscribeVaultOps(vaultId);
      await syncVaultOps(vaultId);
    }
  }

  /// 删除金库时清理：退订 + 清除同步位点。
  Future<void> removeVaultSyncState(String vaultId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'sync_state',
      where: 'key = ?',
      whereArgs: ['vault_ops_cursor:$vaultId'],
    );
    await SupabaseManager.instance.unsubscribeVaultOps(vaultId);
  }

  Future<int> _getVaultCursor(DatabaseExecutor db, String vaultId) async {
    final rows = await db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: ['vault_ops_cursor:$vaultId'],
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String) ?? 0;
  }

  Future<void> _setVaultCursor(
    DatabaseExecutor db,
    String vaultId,
    int cursor,
  ) async {
    await db.insert('sync_state', {
      'key': 'vault_ops_cursor:$vaultId',
      'value': '$cursor',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}