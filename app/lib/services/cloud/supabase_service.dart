import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/log.dart';

/// Supabase 基础设施：初始化、邮箱认证、ledgers/ledgerOps 存取、Realtime 订阅。
///
/// 发布版由构建注入配置（--dart-define-from-file），初始化失败时保持
/// 「未就绪」但不抛错。所有云端方法失败返回空结果/ false，
/// 由上层同步引擎决定是否重试。
class SupabaseManager {
  SupabaseManager._();

  static final SupabaseManager instance = SupabaseManager._();

  bool _ready = false;

  /// 是否已初始化并持有有效配置
  bool get isReady => _ready;

  /// 就绪后的客户端；未就绪时为 null
  SupabaseClient? get client => _ready ? Supabase.instance.client : null;

  /// 已登录用户 id；真实邮箱认证登录后才有（不再匿名登录）
  String? get uid => client?.auth.currentUser?.id;

  /// 已登录账号的邮箱（author_id），未登录为 null。
  String? get email => client?.auth.currentUser?.email;

  Future<void> init() async {
    if (_ready) return;
    try {
      // 发布版通过 --dart-define-from-file 注入，配置恒存在；未注入时为空字符串。
      await Supabase.initialize(
        url: const String.fromEnvironment('SUPABASE_URL'),
        publishableKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      ).timeout(const Duration(seconds: 15));
      _ready = true;
    } catch (e) {
      appLog('[sync] init failed: $e');
      _ready = false;
    }
  }

  /// 确保已用真实账号（邮箱+密码）登录。返回是否已登录。
  /// 不再匿名登录：共享账本参与需要真实账号身份。
  Future<bool> ensureSignedIn() async {
    final client = this.client;
    if (client == null) return false;
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous) return false;
    return true;
  }

  /// 用邮箱注册。成功返回 true；邮箱已存在/失败返回 false。
  Future<bool> signUpWithEmail(String email, String password) async {
    final client = this.client;
    if (client == null) return false;
    try {
      await client.auth
          .signUp(email: email, password: password)
          .timeout(const Duration(seconds: 15));
      return true;
    } catch (e) {
      appLog('[sync] signUp failed: $e');
      return false;
    }
  }

  /// 邮箱+密码登录。成功返回 true；凭据错误/失败返回 false。
  Future<bool> signInWithEmail(String email, String password) async {
    final client = this.client;
    if (client == null) return false;
    try {
      await client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));
      return true;
    } catch (e) {
      appLog('[sync] signIn failed: $e');
      return false;
    }
  }

  /// 退出登录。
  Future<void> signOut() async {
    final client = this.client;
    if (client == null) return;
    try {
      await client.auth.signOut();
    } catch (e) {
      appLog('[sync] signOut failed: $e');
    }
  }

  // ==================== ledgers（房间 = 共享账本）====================

  /// 新建房间。房间 id 由本地账本 id 直接充当，保证双端一致。
  /// 云端已有同 id 房间（重复开启/历史残留）则复用并返回其邀请码；
  /// 创建失败返回 null。
  Future<String?> createLedger({
    required String ledgerId,
    required String name,
    required String inviteCode,
  }) async {
    final client = this.client;
    final myEmail = email;
    if (client == null || myEmail == null) return null;
    try {
      final existing = await fetchLedger(ledgerId);
      if (existing != null) {
        return existing['invite_code']?.toString();
      }
      await client.from('ledger').insert({
        'id': ledgerId,
        'name': name,
        'owner_id': myEmail,
        'members': [myEmail],
        'invite_code': inviteCode,
        'seq': 0,
      });
      return inviteCode;
    } catch (e) {
      appLog('[sync] createLedger failed: $e');
      final existing = await fetchLedger(ledgerId);
      return existing?['invite_code']?.toString();
    }
  }

  /// 按房间 id（= 账本 id）取房间
  Future<Map<String, dynamic>?> fetchLedger(String ledgerId) async {
    final client = this.client;
    if (client == null) return null;
    try {
      return await client.from('ledger').select().eq('id', ledgerId).maybeSingle();
    } catch (e) {
      appLog('[sync] fetchLedger failed: $e');
      return null;
    }
  }

  /// 用邀请码加入房间（原子操作 RPC：查房间 + 把自己加入 members）。
  ///
  /// 返回房间数据；邀请码无效返回 null；网络/超时/服务端 RPC 异常原样上抛，
  /// 由上层 [SyncService.joinByInvite] 按类型区分提示。
  Future<Map<String, dynamic>?> joinLedgerByInvite(String inviteCode) async {
    final client = this.client;
    if (client == null) throw StateError('Supabase 未就绪');
    final res = await client.rpc(
      'join_by_invite',
      params: {'p_invite_code': inviteCode.trim().toUpperCase()},
    );
    if (res is Map<String, dynamic>) return res;
    // RPC 对不存在的邀请码返回 null（见 join_by_invite 的 `return null`）。
    return null;
  }

  /// 改房间名（共享账本改名同步给对方）
  Future<bool> renameLedger(String ledgerId, String name) async {
    final client = this.client;
    if (client == null) return false;
    try {
      await client
          .from('ledger')
          .update({
            'name': name,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', ledgerId);
      return true;
    } catch (e) {
      appLog('[sync] renameLedger failed: $e');
      return false;
    }
  }

  // ==================== ledgerOps（操作日志，增量同步载体）====================

  /// 追加一条操作日志。成功返回云端自增 id，失败返回 null。
  Future<int?> appendLedgerOp({
    required String ledgerId,
    required String entityType,
    required String entityId,
    required String op,
    required Map<String, dynamic> payload,
    required String deviceId,
  }) async {
    final client = this.client;
    final myUid = uid;
    if (client == null || myUid == null) return null;
    try {
      final row = await client
          .from('ledger_ops')
          .insert({
            'ledger_id': ledgerId,
            'entity_type': entityType,
            'entity_id': entityId,
            'op': op,
            'payload': payload,
            'uid': myUid,
            'device_id': deviceId,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();
      final id = row['id'];
      return id is int ? id : int.tryParse(id.toString());
    } catch (e) {
      appLog('[sync] appendLedgerOp failed: $e');
      return null;
    }
  }

  /// 拉取房间内 id 大于 [afterId] 的增量日志（按 id 升序）。
  Future<List<Map<String, dynamic>>> fetchLedgerOps(
    String ledgerId, {
    required int afterId,
    int limit = 200,
  }) async {
    final client = this.client;
    if (client == null) return const [];
    try {
      return await client
          .from('ledger_ops')
          .select()
          .eq('ledger_id', ledgerId)
          .gt('id', afterId)
          .order('id', ascending: true)
          .limit(limit);
    } catch (e) {
      appLog('[sync] fetchLedgerOps failed: $e');
      return const [];
    }
  }

  // ==================== vaults（多人金库房间）====================

  /// 新建多人金库房间。id 用本地小金库账户 id 直接充当，保证双端一致。
  /// 成功返回邀请码；网络/服务端 RPC 异常原样上抛，由上层区分提示。
  Future<String?> createVault({
    required String vaultId,
    required String name,
    required String inviteCode,
    String remark = '',
  }) async {
    final client = this.client;
    if (client == null) return null;
    final res = await client.rpc(
      'create_vault',
      params: {
        'p_id': vaultId,
        'p_name': name,
        'p_invite_code': inviteCode.trim().toUpperCase(),
        'p_remark': remark,
      },
    );
    if (res is Map) {
      return res['invite_code']?.toString();
    }
    return null;
  }

  /// 用邀请码加入多人金库。返回金库数据；邀请码无效/已被占用返回 null。
  Future<Map<String, dynamic>?> joinVaultByInvite(String inviteCode) async {
    final client = this.client;
    if (client == null) throw StateError('Supabase 未就绪');
    final res = await client.rpc(
      'join_vault_by_invite',
      params: {'p_invite_code': inviteCode.trim().toUpperCase()},
    );
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  /// 删除多人金库房间（仅 owner / peer 本人可删），级联清理其事件。
  Future<bool> deleteVault(String vaultId) async {
    final client = this.client;
    if (client == null) return false;
    try {
      final res = await client.rpc('delete_vault', params: {'p_id': vaultId});
      return res == true;
    } catch (e) {
      appLog('[sync] deleteVault failed: $e');
      return false;
    }
  }

  /// 拉取我参与（owner 或 peer）的全部多人金库。
  Future<List<Map<String, dynamic>>> fetchMyVaults() async {
    final client = this.client;
    if (client == null) return const [];
    try {
      final res = await client
          .from('vaults')
          .select('id,name,created_at,invite_code,owner_email,peer_email');
      return res
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      appLog('[sync] fetchMyVaults failed: $e');
      return const [];
    }
  }

  /// 追加一条金库存取事件日志。幂等：云端 vault_ops.entity_id 唯一，
  /// 若该 entity_id 已存在则直接复用其 id（重试/重复提交安全）。
  Future<int?> appendVaultOp({
    required String vaultId,
    required String entityId,
    required String op,
    required Map<String, dynamic> payload,
    required String deviceId,
  }) async {
    final client = this.client;
    final myUid = uid;
    if (client == null || myUid == null) return null;
    try {
      final existing = await client
          .from('vault_ops')
          .select('id')
          .eq('vault_id', vaultId)
          .eq('entity_id', entityId)
          .maybeSingle();
      if (existing != null) {
        final id = existing['id'];
        return id is int ? id : int.tryParse(id.toString());
      }
      final row = await client
          .from('vault_ops')
          .insert({
            'vault_id': vaultId,
            'entity_id': entityId,
            'op': op,
            'payload': payload,
            'uid': myUid,
            'device_id': deviceId,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();
      final id = row['id'];
      return id is int ? id : int.tryParse(id.toString());
    } catch (e) {
      appLog('[sync] appendVaultOp failed: $e');
      return null;
    }
  }

  // ==================== Realtime 订阅 ====================

  RealtimeChannel? _ledgerChannel;
  final Map<String, RealtimeChannel> _ledgerOpChannels = {};

  /// 订阅指定房间的 ledgerOps INSERT：对方写一笔立即收到，触发增量拉取。
  /// 每个房间单独持有一条通道，重复订阅同房间会先关闭旧通道。
  Future<void> subscribeLedgerOps({
    required String ledgerId,
    required void Function(PostgresChangePayload payload) callback,
  }) async {
    final client = this.client;
    if (client == null) return;
    final existing = _ledgerOpChannels.remove(ledgerId);
    if (existing != null) {
      await existing.unsubscribe();
    }
    final channel = client
        .channel('ledger_ops:$ledgerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ledger_ops',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ledger_id',
            value: ledgerId,
          ),
          callback: callback,
        )
        // 连接失败由 SDK 内置 timeout(默认 10s)+回调状态兜底，不阻塞调用方。
        .subscribe();
    _ledgerOpChannels[ledgerId] = channel;
  }

  /// 退订指定房间的实时通道（删除共享账本时清理）。
  Future<void> unsubscribeLedgerOps(String ledgerId) async {
    final channel = _ledgerOpChannels.remove(ledgerId);
    if (channel != null) {
      await channel.unsubscribe();
    }
  }

  /// 订阅 ledgers 的 UPDATE/INSERT，用于账本改名、成员加入等变化实时感知。
  /// 广播全表，回调内由上层按房间 id 过滤。
  Future<void> subscribeLedgers({
    required void Function(PostgresChangePayload payload) callback,
  }) async {
    final client = this.client;
    if (client == null) return;
    await _ledgerChannel?.unsubscribe();
    _ledgerChannel = client
        .channel('ledger:all')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ledger',
          callback: callback,
        )
        .subscribe();
  }

  Future<void> disposeChannels() async {
    for (final channel in _ledgerOpChannels.values) {
      await channel.unsubscribe();
    }
    _ledgerOpChannels.clear();
    await _ledgerChannel?.unsubscribe();
    _ledgerChannel = null;
  }

  // ==================== profiles（昵称/头像，author_id 维度）====================

  static const _avatarsBucket = 'avatars';

  /// 上传头像到公开桶，返回公开 URL；失败返回 null。
  /// 文件名建议带版本（如 authorId_时间戳），使每次头像 URL 不同，
  /// 以避开同名覆盖后客户端仍命中旧 URL 缓存的刷新问题。
  Future<String?> uploadAvatar(
    String authorId,
    String localPath, {
    String? fileName,
  }) async {
    final client = this.client;
    if (client == null) return null;
    try {
      final path = fileName ?? '$authorId.jpg';
      final file = File(localPath);
      await client.storage
          .from(_avatarsBucket)
          .upload(path, file, fileOptions: const FileOptions(upsert: true));
      return client.storage.from(_avatarsBucket).getPublicUrl(path);
    } catch (e) {
      appLog('[sync] uploadAvatar failed: $e');
      return null;
    }
  }

  /// upsert 一条 profile（author_id 主键）；[avatarUrl] 为可选的单独更新。
  /// 写入成功返回 true；云端未就绪或超时/失败返回 false，调用方可据此提示用户。
  Future<bool> upsertProfile({
    required String authorId,
    String? nickname,
    String? avatarUrl,
  }) async {
    final client = this.client;
    if (client == null) return false;
    try {
      await client
          .from('profiles')
          .upsert({
            'author_id': authorId,
            'nickname': ?nickname,
            'avatar_url': ?avatarUrl,
          })
          .timeout(const Duration(seconds: 15));
      return true;
    } catch (e) {
      appLog('[sync] upsertProfile failed: $e');
      return false;
    }
  }

  /// 按 author_id 查昵称；未就绪或无记录返回 null。
  Future<String?> getProfileNickname(String authorId) async {
    final client = this.client;
    if (client == null) return null;
    try {
      final res = await client
          .from('profiles')
          .select('nickname')
          .eq('author_id', authorId)
          .maybeSingle();
      return res?['nickname'] as String?;
    } catch (e) {
      appLog('[sync] getProfileNickname failed: $e');
      return null;
    }
  }

  /// 按 author_id 查头像 URL；未就绪或无记录返回 null。
  Future<String?> getProfileAvatar(String authorId) async {
    final client = this.client;
    if (client == null) return null;
    try {
      final res = await client
          .from('profiles')
          .select('avatar_url')
          .eq('author_id', authorId)
          .maybeSingle();
      final url = res?['avatar_url'] as String?;
      return (url == null || url.isEmpty) ? null : url;
    } catch (e) {
      appLog('[sync] getProfileAvatar failed: $e');
      return null;
    }
  }

  /// 拉取当前账号所属的全部房间（RLS 已限定为成员）。
  /// 换新设备/清数据后登录时，据此恢复本地共享账本列表。
  Future<List<Map<String, dynamic>>> fetchMyLedgers() async {
    final client = this.client;
    if (client == null) return const [];
    try {
      final res = await client.from('ledger').select('id,name,created_at,invite_code');
      return res
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      appLog('[sync] fetchMyLedgers failed: $e');
      return const [];
    }
  }

  /// 拉取全部成员资料（author_id/nickname/avatar_url）。
  /// 用于新设备/清数据登录后以 profiles 表为权威源恢复昵称头像，
  /// 不依赖 ledgerOps 历史事件。失败返回空表，由上层自行容忍。
  Future<List<Map<String, dynamic>>> fetchAllProfiles() async {
    final client = this.client;
    if (client == null) return const [];
    try {
      final res = await client
          .from('profiles')
          .select('author_id,nickname,avatar_url');
      return res
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      appLog('[sync] fetchAllProfiles failed: $e');
      return const [];
    }
  }
}
