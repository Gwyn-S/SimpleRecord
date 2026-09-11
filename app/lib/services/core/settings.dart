import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/app_paths.dart';

/// 极简 JSON 配置存储，替代 shared_preferences 插件。
/// 文件固定为 <应用基础目录>/simplerecord.json，写入时格式化缩进便于阅读。
class Settings {
  Settings._();

  static Map<String, dynamic> _cache = {};
  static bool _loaded = false;

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
        if (decoded is Map<String, dynamic>) _cache = decoded;
      } catch (_) {
        _cache = {};
      }
    }
    _loaded = true;
    return _cache;
  }

  static Future<void> _persist() async {
    final file = await _file();
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_cache),
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
