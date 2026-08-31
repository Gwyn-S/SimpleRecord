import 'package:uuid/uuid.dart';

import '../pages/../services/settings.dart';
import 'supabase_service.dart';

// 昵称本地与云端的上传/恢复，author_id 绑定换设备身份。
class AuthorService {
  AuthorService._();

  static final AuthorService instance = AuthorService._();

  static const _keyAuthorId = 'author_id';

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
    final nickname = await Settings.getString('nickname');
    if (nickname == null || nickname.trim().isEmpty) return;
    await SupabaseManager.instance.upsertProfile(
      authorId: id,
      nickname: nickname.trim(),
    );
  }

  /// 用旧 author_id 从云端拉昵称并写回本地 Settings（换设备恢复）。
  /// 返回恢复到的昵称；云端无记录或未就绪返回 null。
  Future<String?> restoreNickname(String authorId) async {
    final nickname = await SupabaseManager.instance
        .getProfileNickname(authorId);
    if (nickname == null || nickname.trim().isEmpty) return null;
    await Settings.setString('nickname', nickname.trim());
    await Settings.setString(_keyAuthorId, authorId);
    return nickname;
  }
}
