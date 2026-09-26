import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/app_paths.dart';

/// 极简 JSON 配置存储，替代 shared_preferences 插件。
/// 文件固定为 <应用基础目录>/simplerecord.json。
///
/// 磁盘上是按业务分节的嵌套结构（见 [_sectionOf] 的归类），
/// 内存 [Settings] 内仍以扁平 key-value 工作，读写调用方无需感知分层。
class Settings {
  Settings._();

  static Map<String, dynamic> _cache = {};
  static bool _loaded = false;

  /// 分节输出顺序（决定文件里分组的先后）。
  static const List<String> _sectionOrder = [
    'app',
    'author',
    'sync',
    'ai',
    'webdav',
    'auto_backup',
  ];

  /// 把扁平 key 归入某个分节。规则按实际 key 前缀/整体匹配，
  /// 命中即返回分节名；未识别的一律归入 'app'。
  static String _sectionOf(String key) {
    if (key.startsWith('nickname_of_') ||
        key.startsWith('avatar_of_') ||
        key == 'nickname' ||
        key == 'avatar_url' ||
        key == 'record_author_display') {
      return 'author';
    }
    if (key == 'device_id') return 'sync';
    if (key.startsWith('ai_')) return 'ai';
    if (key.startsWith('webdav_auto_backup_') ||
        key.startsWith('local_auto_backup_')) {
      return 'auto_backup';
    }
    if (key.startsWith('webdav_')) return 'webdav';
    return 'app';
  }

  static Future<File> _file() async {
    final dir = await appBaseDirectory();
    final file = File(p.join(dir.path, 'simplerecord.json'));
    file.parent.createSync(recursive: true);
    return file;
  }

  static Future<Map<String, dynamic>> _ensureLoaded() async {
    if (_loaded) return _cache;
    final file = await _file();
    if (file.existsSync()) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, dynamic>) _cache = _flatten(decoded);
      } catch (_) {
        _cache = {};
      }
    }
    _loaded = true;
    return _cache;
  }

  /// 把磁盘上的分节结构展开为扁平 key-value。
  /// 顶层每节为分节名 -> 子 map,展开后即全量配置。
  static Map<String, dynamic> _flatten(Map<String, dynamic> decoded) {
    final flat = <String, dynamic>{};
    decoded.forEach((k, v) {
      if (v is Map<String, dynamic>) {
        flat.addAll(v);
      }
    });
    return flat;
  }

  static Future<void> _persist() async {
    final file = await _file();
    // 按分节归类：每节的 key 保持原名，仅换外层外壳便于阅读。
    // 只输出有内容的节，顺序固定为 [_sectionOrder]。
    final grouped = <String, Map<String, dynamic>>{};
    for (final s in _sectionOrder) {
      final section = <String, dynamic>{};
      _cache.forEach((k, v) {
        if (_sectionOf(k) == s) section[k] = v;
      });
      if (section.isNotEmpty) grouped[s] = section;
    }
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(grouped),
      flush: true,
    );
  }

  /// 读取字符串配置；不存在时返回 null。
  static Future<String?> getString(String key) async =>
      (await _ensureLoaded())[key] as String?;

  /// 返回所有以 [prefix] 开头的字符串键值（用于按前缀批量读取映射）。
  static Future<Map<String, String>> stringMapByPrefix(String prefix) async {
    final data = await _ensureLoaded();
    final result = <String, String>{};
    data.forEach((k, v) {
      if (k.startsWith(prefix) && v is String) result[k] = v;
    });
    return result;
  }

  /// 写入字符串配置并落盘。
  static Future<void> setString(String key, String value) async {
    await _ensureLoaded();
    _cache[key] = value;
    await _persist();
  }

  /// 批量写入多个字符串并只落盘一次，避免逐条写盘。
  static Future<void> setStrings(Map<String, String> entries) async {
    await _ensureLoaded();
    _cache.addAll(entries);
    await _persist();
  }

  /// 读取整型配置；不存在时返回 null。
  static Future<int?> getInt(String key) async =>
      (await _ensureLoaded())[key] as int?;

  /// 写入整型配置并落盘。
  static Future<void> setInt(String key, int value) async {
    await _ensureLoaded();
    _cache[key] = value;
    await _persist();
  }

  /// 读取布尔配置；不存在时返回 null。
  static Future<bool?> getBool(String key) async =>
      (await _ensureLoaded())[key] as bool?;

  /// 写入布尔配置并落盘。
  static Future<void> setBool(String key, bool value) async {
    await _ensureLoaded();
    _cache[key] = value;
    await _persist();
  }

  /// 删除指定配置项并落盘。
  static Future<void> remove(String key) async {
    await _ensureLoaded();
    _cache.remove(key);
    await _persist();
  }
}
