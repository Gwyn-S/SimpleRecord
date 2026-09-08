import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_config.dart';
import '../utils/log.dart';

/// Supabase 基础设施：初始化、匿名登录、rooms/oplogs 存取、Realtime 订阅。
///
/// 未配置 URL/anonKey 时保持「未就绪」但不抛错，等待用户在设置页填写
/// 后重新 [init]。所有云端方法失败返回空结果，由上层同步引擎决定是否重试。
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
    final config = await loadCloudConfig();
    if (!config.isConfigured) return;
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabaseAnonKey,
      );
      _ready = true;
    } catch (e) {
      appLog('[sync] init failed: $e');
      _ready = false;
    }
  }

  /// 是否已初始化过 Supabase。
  /// 从未初始化时直接访问 [Supabase.instance] 会抛
  /// "You must initialize the supabase instance"，这里安全探测。
  static bool isSupabaseInitialized() {
    try {
      return Supabase.instance.isInitialized;
    } catch (_) {
      return false;
    }
  }

  /// 配置变更后重建连接：释放旧客户端（含 auth/实时通道），下次 init 以新配置初始化。
  Future<void> reconnect() async {
    if (SupabaseManager.isSupabaseInitialized()) {
      try {
        await Supabase.instance.dispose();
      } catch (_) {
        // 释放旧实例失败不影响后续用新配置重新初始化
      }
    }
    _ready = false;
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
      await client.auth.signUp(email: email, password: password);
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
      await client.auth.signInWithPassword(email: email, password: password);
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

  // ==================== rooms（房间 = 共享账本）====================

  /// 新建房间。房间 id 由本地账本 id 直接充当，保证双端一致。
  /// 云端已有同 id 房间（重复开启/历史残留）则复用并返回其邀请码；
  /// 创建失败返回 null。
  Future<String?> createRoom({
    required String roomId,
    required String name,
    required String inviteCode,
  }) async {
    final client = this.client;
    final myEmail = email;
    if (client == null || myEmail == null) return null;
    try {
      final existing = await fetchRoom(roomId);
      if (existing != null) {
        return existing['invite_code']?.toString();
      }
      await client.from('rooms').insert({
        'id': roomId,
        'name': name,
        'owner_id': myEmail,
        'members': [myEmail],
        'invite_code': inviteCode,
        'seq': 0,
      });
      return inviteCode;
    } catch (e) {
      appLog('[sync] createRoom failed: $e');
      final existing = await fetchRoom(roomId);
      return existing?['invite_code']?.toString();
    }
  }

  /// 按房间 id（= 账本 id）取房间
  Future<Map<String, dynamic>?> fetchRoom(String roomId) async {
    final client = this.client;
    if (client == null) return null;
    try {
      return await client.from('rooms').select().eq('id', roomId).maybeSingle();
    } catch (e) {
      appLog('[sync] fetchRoom failed: $e');
      return null;
    }
  }

  /// 用邀请码加入房间（原子操作 RPC：查房间 + 把自己加入 members）。
  /// 返回房间数据；邀请码无效/未登录/失败返回 null。
  Future<Map<String, dynamic>?> joinRoomByInvite(String inviteCode) async {
    final client = this.client;
    if (client == null) return null;
    try {
      final res = await client.rpc(
        'join_by_invite',
        params: {'p_invite_code': inviteCode.trim().toUpperCase()},
      );
      if (res is Map<String, dynamic>) return res;
      appLog('[sync] joinRoomByInvite: unexpected result ${res.runtimeType}');
      return null;
    } catch (e) {
      appLog('[sync] joinRoomByInvite failed: $e');
      return null;
    }
  }

  /// 改房间名（共享账本改名同步给对方）
  Future<bool> renameRoom(String roomId, String name) async {
    final client = this.client;
    if (client == null) return false;
    try {
      await client
          .from('rooms')
          .update({
            'name': name,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', roomId);
      return true;
    } catch (e) {
      appLog('[sync] renameRoom failed: $e');
      return false;
    }
  }

  // ==================== oplogs（操作日志，增量同步载体）====================

  /// 追加一条操作日志。成功返回云端自增 id，失败返回 null。
  Future<int?> appendOplog({
    required String roomId,
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
          .from('oplogs')
          .insert({
            'room_id': roomId,
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
      appLog('[sync] appendOplog failed: $e');
      return null;
    }
  }

  /// 拉取房间内 id 大于 [afterId] 的增量日志（按 id 升序）。
  Future<List<Map<String, dynamic>>> fetchOplogs(
    String roomId, {
    required int afterId,
    int limit = 200,
  }) async {
    final client = this.client;
    if (client == null) return const [];
    try {
      return await client
          .from('oplogs')
          .select()
          .eq('room_id', roomId)
          .gt('id', afterId)
          .order('id', ascending: true)
          .limit(limit);
    } catch (e) {
      appLog('[sync] fetchOplogs failed: $e');
      return const [];
    }
  }

  // ==================== Realtime 订阅 ====================

  RealtimeChannel? _roomChannel;
  final Map<String, RealtimeChannel> _oplogChannels = {};

  /// 订阅指定房间的 oplogs INSERT：对方写一笔立即收到，触发增量拉取。
  /// 每个房间单独持有一条通道，重复订阅同房间会先关闭旧通道。
  Future<void> subscribeOplogs({
    required String roomId,
    required void Function(PostgresChangePayload payload) callback,
  }) async {
    final client = this.client;
    if (client == null) return;
    final existing = _oplogChannels.remove(roomId);
    if (existing != null) {
      await existing.unsubscribe();
    }
    final channel = client
        .channel('oplogs:$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'oplogs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: callback,
        )
        .subscribe();
    _oplogChannels[roomId] = channel;
  }

  /// 退订指定房间的实时通道（删除共享账本时清理）。
  Future<void> unsubscribeOplogs(String roomId) async {
    final channel = _oplogChannels.remove(roomId);
    if (channel != null) {
      await channel.unsubscribe();
    }
  }

  /// 订阅 rooms 的 UPDATE/INSERT，用于账本改名、成员加入等变化实时感知。
  /// 广播全表，回调内由上层按房间 id 过滤。
  Future<void> subscribeRooms({
    required void Function(PostgresChangePayload payload) callback,
  }) async {
    final client = this.client;
    if (client == null) return;
    await _roomChannel?.unsubscribe();
    _roomChannel = client
        .channel('rooms:all')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rooms',
          callback: callback,
        )
        .subscribe();
  }

  Future<void> disposeChannels() async {
    for (final channel in _oplogChannels.values) {
      await channel.unsubscribe();
    }
    _oplogChannels.clear();
    await _roomChannel?.unsubscribe();
    _roomChannel = null;
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
  Future<List<Map<String, dynamic>>> fetchMyRooms() async {
    final client = this.client;
    if (client == null) return const [];
    try {
      final res = await client.from('rooms').select('id,name,created_at,invite_code');
      return res
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      appLog('[sync] fetchMyRooms failed: $e');
      return const [];
    }
  }

  /// 拉取全部成员资料（author_id/nickname/avatar_url）。
  /// 用于新设备/清数据登录后以 profiles 表为权威源恢复昵称头像，
  /// 不依赖 oplogs 历史事件。失败返回空表，由上层自行容忍。
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
