import 'package:uuid/uuid.dart';

import 'settings.dart';
import 'supabase_service.dart';
import '../models/record.dart';

// 昵称/头像本地与云端的上传、恢复与展示反查。author_id 绑定换设备身份。
//
// 昵称/头像都有两套来源：
//  - 本机自己的存 Settings['nickname'] / Settings['avatar_url']；
//  - 别人（author_id）的最新值，经下行 profile 事件写进
//    Settings['nickname_of_<authorId>'] / Settings['avatar_of_<authorId>']
//    并缓存在内存 [_names] / [_avatars]。
// 展示时按 Record.authorId 反查最新值，查不到则保留原快照。
class AuthorService {
  AuthorService._();

  static final AuthorService instance = AuthorService._();

  static const _keyAuthorId = 'author_id';
  static const _keyNamePrefix = 'nickname_of_';
  static const _keyAvatarPrefix = 'avatar_of_';
  static const _keyOwnNickname = 'nickname';
  static const _keyOwnAvatar = 'avatar_url';

  final Map<String, String> _names = {};
  final Map<String, String> _avatars = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final names = await Settings.stringMapByPrefix(_keyNamePrefix);
    names.forEach((key, name) {
      final id = key.substring(_keyNamePrefix.length);
      if (id.isNotEmpty && name.isNotEmpty) _names[id] = name;
    });
    final avatars = await Settings.stringMapByPrefix(_keyAvatarPrefix);
    avatars.forEach((key, url) {
      final id = key.substring(_keyAvatarPrefix.length);
      if (id.isNotEmpty && url.isNotEmpty) _avatars[id] = url;
    });
    _loaded = true;
  }

  /// 记录/更新某 author_id 的最新昵称。
  Future<void> registerNickname(String authorId, String nickname) async {
    final n = nickname.trim();
    if (authorId.isEmpty || n.isEmpty) return;
    _names[authorId] = n;
    await Settings.setString('$_keyNamePrefix$authorId', n);
  }

  /// 记录/更新某 author_id 的最新头像 URL；传空/null 表示清除。
  Future<void> registerAvatar(String authorId, String? url) async {
    if (authorId.isEmpty) return;
    final u = url?.trim() ?? '';
    if (u.isEmpty) {
      _avatars.remove(authorId);
      await Settings.remove('$_keyAvatarPrefix$authorId');
    } else {
      _avatars[authorId] = u;
      await Settings.setString('$_keyAvatarPrefix$authorId', u);
    }
  }

  /// 取本机昵称；未设置返回 null。
  Future<String?> ownNickname() async {
    final n = await Settings.getString(_keyOwnNickname);
    if (n == null || n.trim().isEmpty) return null;
    return n.trim();
  }

  /// 取本机头像 URL；未设置返回 null。
  Future<String?> ownAvatar() async {
    final u = await Settings.getString(_keyOwnAvatar);
    if (u == null || u.trim().isEmpty) return null;
    return u.trim();
  }

  /// 取本机 author_id，不存在则生成一个永久的 UUID 并存进 Settings。
  Future<String> ensureAuthorId() async {
    final existing = await Settings.getString(_keyAuthorId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await Settings.setString(_keyAuthorId, id);
    return id;
  }

  /// 把昵称同步到云端 profiles。未就绪时静默失败。
  Future<void> syncNicknameToCloud() async {
    final id = await ensureAuthorId();
    final nickname = await ownNickname();
    if (nickname == null) return;
    await registerNickname(id, nickname);
    await SupabaseManager.instance.upsertProfile(
      authorId: id,
      nickname: nickname,
    );
  }

  /// 用旧 author_id 从云端拉昵称并写回本地（换设备恢复）。
  Future<String?> restoreNickname(String authorId) async {
    final nickname =
        await SupabaseManager.instance.getProfileNickname(authorId);
    if (nickname == null || nickname.trim().isEmpty) return null;
    final n = nickname.trim();
    await Settings.setString(_keyOwnNickname, n);
    await Settings.setString(_keyAuthorId, authorId);
    await registerNickname(authorId, n);
    return n;
  }

  /// 用旧 author_id 从云端拉头像 URL 并写回本地（换设备恢复）。
  Future<String?> restoreAvatar(String authorId) async {
    final url = await SupabaseManager.instance.getProfileAvatar(authorId);
    if (url != null && url.isNotEmpty) {
      await Settings.setString(_keyOwnAvatar, url);
    }
    await registerAvatar(authorId, url);
    return url;
  }

  /// 改头像：上传到公开桶，回写本机 + 云端 profile。返回公开 URL；失败返回 null。
  Future<String?> changeAvatar(String localPath) async {
    final id = await ensureAuthorId();
    final url = await SupabaseManager.instance.uploadAvatar(id, localPath);
    if (url == null) return null;
    await Settings.setString(_keyOwnAvatar, url);
    await registerAvatar(id, url);
    await SupabaseManager.instance
        .upsertProfile(authorId: id, avatarUrl: url);
    return url;
  }

  /// 反查 author_id 的展示昵称；未知返回 null。
  Future<String?> displayNameFor(String authorId) async {
    await _ensureLoaded();
    final ownId = await ensureAuthorId();
    if (ownId == authorId) {
      final own = await ownNickname();
      if (own != null) _names[ownId] = own;
    }
    return _names[authorId];
  }

  /// 反查 author_id 的展示头像 URL；未知返回 null。
  Future<String?> displayAvatarFor(String authorId) async {
    await _ensureLoaded();
    final ownId = await ensureAuthorId();
    if (ownId == authorId) {
      final own = await ownAvatar();
      if (own != null) _avatars[ownId] = own;
    }
    return _avatars[authorId];
  }

  /// 把记录列表的 author / authorAvatarUrl 替换为 author_id 对应最新值。
  Future<List<Record>> applyLatestNicknames(List<Record> records) async {
    await _ensureLoaded();
    final ownId = await ensureAuthorId();
    final ownName = await ownNickname();
    if (ownName != null) _names[ownId] = ownName;
    final myAvatar = await ownAvatar();
    if (myAvatar != null) _avatars[ownId] = myAvatar;
    return [
      for (final r in records)
        if (r.authorId != null && _names.containsKey(r.authorId))
          r.copyWith(
            author: _names[r.authorId],
            authorAvatarUrl: _avatars[r.authorId],
          )
        else
          r,
    ];
  }
}
