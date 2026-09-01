import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'image_storage_service.dart';
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

  /// 只读本机 author_id；未生成过返回 null，不触发创建。
  Future<String?> existingAuthorId() async {
    final existing = await Settings.getString(_keyAuthorId);
    if (existing == null || existing.isEmpty) return null;
    return existing;
  }

  /// 主动生成并持久化一个全新的 author_id，并清空本机昵称/头像（全新身份）。
  Future<String> createNewAuthorId() async {
    final id = const Uuid().v4();
    await Settings.setString(_keyAuthorId, id);
    await Settings.remove(_keyOwnNickname);
    await Settings.remove(_keyOwnAvatar);
    _names.remove(id);
    _avatars.remove(id);
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

  /// 改头像：上传原图到公开桶，回写本机 + 云端 profile。
  /// 返回公开 URL；失败返回 null。文件名带时间戳版本，保证每次 URL 不同
  /// 以绕开客户端旧 URL 缓存。服务器存原图，本地展示缓存由 [_fetchAndCache] 压缩。
  Future<String?> changeAvatar(String localPath) async {
    final id = await ensureAuthorId();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ext = p.extension(localPath);
    final url = await SupabaseManager.instance
        .uploadAvatar(id, localPath, fileName: '${id}_$stamp$ext');
    if (url == null) return null;
    await Settings.setString(_keyOwnAvatar, url);
    await registerAvatar(id, url);
    await SupabaseManager.instance
        .upsertProfile(authorId: id, avatarUrl: url);
    return url;
  }

  /// 用 dart:ui 把图片字节缩放为最长边 [maxEdge] 的 PNG 字节。
  /// dart:ui 仅支持 PNG 编码，故以 128px 控制体积（14/64px 显示足够）。
  static Future<Uint8List?> _resizeBytes(Uint8List bytes,
      {int maxEdge = 128}) async {
    final ui.Image? decoded;
    try {
      decoded = await decodeImage(bytes);
    } catch (e) {
      debugPrint('[avatar] decode failed: $e');
      return null;
    }
    if (decoded == null) return null;
    final w = decoded.width;
    final h = decoded.height;
    final scale = maxEdge / (w > h ? w : h);
    final targetW = (w * scale).round().clamp(1, 4096);
    final targetH = (h * scale).round().clamp(1, 4096);
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetW,
      targetHeight: targetH,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  /// 用 ui.ImageCodec 解码图像字节，返回 ui.Image（失败返回 null）。
  static Future<ui.Image?> decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// 反查 author_id 的展示昵称；未知返回 null。
  Future<String?> displayNameFor(String authorId) async {
    await _ensureLoaded();
    final ownId = await existingAuthorId();
    if (ownId != null && ownId == authorId) {
      final own = await ownNickname();
      if (own != null) _names[ownId] = own;
    }
    return _names[authorId];
  }

  /// 反查 author_id 的展示头像 URL；未知返回 null。
  Future<String?> displayAvatarFor(String authorId) async {
    await _ensureLoaded();
    final ownId = await existingAuthorId();
    if (ownId != null && ownId == authorId) {
      final own = await ownAvatar();
      if (own != null) _avatars[ownId] = own;
    }
    return _avatars[authorId];
  }

  /// 把记录列表的 author / authorAvatarUrl 替换为 author_id 对应最新值。
  Future<List<Record>> applyLatestNicknames(List<Record> records) async {
    await _ensureLoaded();
    final ownId = await existingAuthorId();
    if (ownId != null) {
      final ownName = await ownNickname();
      if (ownName != null) _names[ownId] = ownName;
      final myAvatar = await ownAvatar();
      if (myAvatar != null) _avatars[ownId] = myAvatar;
    }
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

  /// 头像磁盘缓存目录路径（进程级缓存，只解析一次，避免每次走 path_provider）。
  static String? _avatarCacheDirPath;

  /// 启动时预热：解析缓存目录路径，使 [cachedAvatarPathSync] 在不依赖异步的情况下可用。
  Future<void> initAvatarCache() async {
    await _avatarCacheDir();
  }

  Future<Directory> _avatarCacheDir() async {
    final cached = _avatarCacheDirPath;
    if (cached != null) return Directory(cached);
    final images = await imagesDirectory();
    final dir = Directory(p.join(images.path, 'avatar_cache'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _avatarCacheDirPath = dir.path;
    return dir;
  }

  /// 同步查询 URL 对应的本地缓存路径；目录未就绪或文件不存在返回 null。
  /// 供首帧 build 同步判断，避免先渲染默认头像再切换。
  String? cachedAvatarPathSync(String url) {
    if (url.isEmpty) return null;
    final dir = _avatarCacheDirPath;
    if (dir == null) return null;
    final path = _avatarCacheFileIn(dir, url);
    try {
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  String _avatarCacheFileIn(String dir, String url) =>
      p.join(dir, '${url.hashCode}.img');

  /// URL -> 本地缓存文件路径 内存缓存，避免同一 URL 重复查盘/下载。
  static final Map<String, String> _urlPathCache = {};

  /// URL -> 下载 Future，同 URL 并发去重：列表同时渲染多个同作者头像时只下载一次。
  static final Map<String, Future<String?>> _urlFetching = {};

  /// 按 URL 拉本地缓存文件；无缓存则从云端下载到缓存目录。
  /// 返回本地文件路径；下载失败返回 null（调用方可回退 NetworkImage）。
  Future<String?> avatarFileForUrl(String url) async {
    if (url.isEmpty) return null;
    final sync = cachedAvatarPathSync(url);
    if (sync != null) {
      _urlPathCache[url] = sync;
      return sync;
    }
    final hit = _urlPathCache[url];
    if (hit != null) return hit;
    final inflight = _urlFetching[url];
    if (inflight != null) return inflight;
    final future = _fetchAndCache(url);
    _urlFetching[url] = future;
    try {
      final path = await future;
      if (path != null) _urlPathCache[url] = path;
      return path;
    } finally {
      _urlFetching.remove(url);
    }
  }

  Future<String?> _fetchAndCache(String url) async {
    final dir = await _avatarCacheDir();
    final file = File(_avatarCacheFileIn(dir.path, url));
    if (file.existsSync()) return file.path;
    try {
      final req = await HttpClient()
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final bytes = await res.fold<List<int>>(
          <int>[], (b, c) => b..addAll(c));
      // 服务器存原图，本地只缓存压缩小图：下载后压缩为 128px PNG 再写盘。
      final small = await _resizeBytes(Uint8List.fromList(bytes));
      await file.writeAsBytes(small ?? bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[avatar] cache download failed: $e');
      return null;
    }
  }
}
