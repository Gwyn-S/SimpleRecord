import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 极简 JSON 配置存储，替代 shared_preferences 插件。
/// 文件固定为 <应用支持目录>/simple_record.json，写入时格式化缩进便于阅读。
class Settings {
  Settings._();

  static Map<String, dynamic> _cache = {};
  static bool _loaded = false;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
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

  static Future<String?> getString(String key) async =>
      (await _ensureLoaded())[key] as String?;

  static Future<void> setString(String key, String value) async {
    await _ensureLoaded();
    _cache[key] = value;
    await _persist();
  }

  static Future<int?> getInt(String key) async =>
      (await _ensureLoaded())[key] as int?;

  static Future<void> setInt(String key, int value) async {
    await _ensureLoaded();
    _cache[key] = value;
    await _persist();
  }

  static Future<bool?> getBool(String key) async =>
      (await _ensureLoaded())[key] as bool?;

  static Future<void> setBool(String key, bool value) async {
    await _ensureLoaded();
    _cache[key] = value;
    await _persist();
  }

  static Future<void> remove(String key) async {
    await _ensureLoaded();
    _cache.remove(key);
    await _persist();
  }
}
