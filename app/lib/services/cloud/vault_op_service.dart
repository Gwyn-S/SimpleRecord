import 'dart:async';
import 'dart:convert';

import '../../models/data/asset_account.dart';
import '../../models/data/transfer.dart';
import '../core/database.dart';
import '../core/cloud_config.dart';
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
      'operator_email': t.operatorEmail.isNotEmpty
          ? t.operatorEmail
          : SupabaseManager.instance.email,
      'operator_nickname': t.operatorNickname,
      'operator_avatar_url': t.operatorAvatarUrl,
    };

    if (fromVault) {
      await _enqueue(
        vaultId: t.fromAccountId,
        entityId: '${t.id}-from',
        op: op == 'delete' ? 'delete' : 'withdraw',
        payload: payloadBase,
      );
    }
    if (toVault) {
      await _enqueue(
        vaultId: t.toAccountId,
        entityId: '${t.id}-to',
        op: op == 'delete' ? 'delete' : 'deposit',
        payload: payloadBase,
      );
    }
    unawaited(flush());
  }

  /// 手动调整余额后入队：金库余额按 delta 记 adjust。
  Future<void> pushAdjust({
    required String accountId,
    required int deltaCents,
    required int beforeCents,
    required int afterCents,
  }) async {
    final accounts = await _loadAccounts();
    final byId = {for (final a in accounts) a.id: a};
    if (!isSharedVault(byId[accountId])) return;

    await _enqueue(
      vaultId: accountId,
      entityId: '$accountId-adj-${DateTime.now().microsecondsSinceEpoch}',
      op: 'adjust',
      payload: {
        'delta_cents': deltaCents,
        'before_cents': beforeCents,
        'after_cents': afterCents,
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
}