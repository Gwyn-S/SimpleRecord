import 'package:uuid/uuid.dart';

import 'settings.dart';
import 'supabase_service.dart';
import '../models/record.dart';

// 昵称本地与云端的上传/恢复，author_id 绑定换设备身份。
//
// 昵称有两套来源：
//  - 本机自己的昵称存 Settings['nickname']；
//  - 别人（author_id）的最新昵称，经下行 profile 事件写进
//    Settings['nickname_of_<authorId>'] 并缓存在内存 [_names]。
// 展示时按 Record.authorId 反查最新昵称，查不到则回退 Record.author 快照。
class AuthorService {
  AuthorService._();

  static final AuthorService instance = AuthorService._();

  static const _keyAuthorId = 'author_id';
  static const _keyNamePrefix = 'nickname_of_';
  static const _keyOwnNickname = 'nickname';

  final Map<String, String> _names = {};
  bool _loaded = false;

  Future<void> _ensureNamesLoaded() async {
    if (_loaded) return;
    final stored = await Settings.stringMapByPrefix(_keyNamePrefix);
    stored.forEach((key, name) {
      final authorId = key.substring(_keyNamePrefix.length);
      if (authorId.isNotEmpty && name.isNotEmpty) _names[authorId] = name;
    });
    _loaded = true;
  }

  /// 记录/更新某 author_id 的最新昵称（对方下行 profile 事件或本机改名时调用）。
  Future<void> registerNickname(String authorId, String nickname) async {
    final n = nickname.trim();
    if (authorId.isEmpty || n.isEmpty) return;
    _names[authorId] = n;
    await Settings.setString('$_keyNamePrefix$authorId', n);
  }

  /// 取本机 author_id 对应昵称（本地昵称）；未设置返回 null。
  Future<String?> ownNickname() async {
    final n = await Settings.getString(_keyOwnNickname);
    if (n == null || n.trim().isEmpty) return null;
    return n.trim();
  }

  /// 取本机 author_id，不存在则生成一个永久的 UUID 并存进 Settings。
  Future<String> ensureAuthorId() async {
    final existing = await Settings.getString(_keyAuthorId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await Settings.setString(_keyAuthorId, id);
    return id;
  }

  /// 把当前昵称同步到云端 profiles（author_id 维度）。未就绪时静默失败。
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

  /// 用旧 author_id 从云端拉昵称并写回本地 Settings（换设备恢复）。
  /// 返回恢复到的昵称；云端无记录或未就绪返回 null。
  Future<String?> restoreNickname(String authorId) async {
    final nickname = await SupabaseManager.instance
        .getProfileNickname(authorId);
    if (nickname == null || nickname.trim().isEmpty) return null;
    final n = nickname.trim();
    await Settings.setString(_keyOwnNickname, n);
    await Settings.setString(_keyAuthorId, authorId);
    await registerNickname(authorId, n);
    return n;
  }

  /// 把记录列表的 author 替换为 author_id 对应的最新昵称；
  /// 无映射时保留原 author（历史快照兼容）。用于账单/搜索等列表展示。
  Future<List<Record>> applyLatestNicknames(List<Record> records) async {
    await _ensureNamesLoaded();
    // 补齐本机自己的映射，避免外显时用旧快照。
    final ownId = await ensureAuthorId();
    if (!_names.containsKey(ownId)) {
      final ownName = await ownNickname();
      if (ownName != null) _names[ownId] = ownName;
    }
    return [
      for (final r in records)
        if (r.authorId != null && _names.containsKey(r.authorId))
          r.copyWith(author: _names[r.authorId])
        else
          r,
    ];
  }

  /// 反查 author_id 的展示昵称；未知返回 null。确保本地映射与本机昵称已登记。
  Future<String?> displayNameFor(String authorId) async {
    await _ensureNamesLoaded();
    final ownId = await ensureAuthorId();
    if (ownId == authorId) {
      final own = await ownNickname();
      if (own != null) _names[ownId] = own;
    }
    return _names[authorId];
  }
}
