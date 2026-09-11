import 'dart:io';

import '../core/settings.dart';
import 'srb_backup_service.dart';
import 'webdav_service.dart';

/// 自动备份频率。
enum AutoBackupFrequency {
  closed('关闭', 0),
  daily('每天', 24),
  weekly('每周', 168),
  monthly('每月', 720);

  const AutoBackupFrequency(this.label, this.hours);

  /// 界面展示文案。
  final String label;

  /// 对应的小时间隔。
  final int hours;

  bool get isClosed => this == closed;

  static AutoBackupFrequency fromName(String? name) {
    return AutoBackupFrequency.values.firstWhere(
      (f) => f.name == name,
      orElse: () => closed,
    );
  }
}

/// 自动备份场景。
enum AutoBackupScene {
  webdav('webdav_'),
  local('local_');

  const AutoBackupScene(this.prefix);

  /// 配置持久化 key 的场景前缀。
  final String prefix;
}

/// 自动备份配置：开关、频率、上次执行时间均按场景（前缀）独立存储。
/// 场景前缀：webdav_（WebDAV 上传）、local_（本地备份）。
class AutoBackupService {
  AutoBackupService._();

  static Future<bool> isEnabled(AutoBackupScene scene) async {
    return await Settings.getBool('${scene.prefix}auto_backup_enabled') ?? false;
  }

  static Future<AutoBackupFrequency> frequency(AutoBackupScene scene) async {
    return AutoBackupFrequency.fromName(
      await Settings.getString('${scene.prefix}auto_backup_frequency'),
    );
  }

  /// 保存开关与频率设置（仅写入给定非空项）。
  static Future<void> save(AutoBackupScene scene, {bool? enabled, AutoBackupFrequency? freq}) async {
    if (enabled != null) {
      await Settings.setBool('${scene.prefix}auto_backup_enabled', enabled);
    }
    if (freq != null) {
      await Settings.setString('${scene.prefix}auto_backup_frequency', freq.name);
    }
  }

  static Future<void> markDone(AutoBackupScene scene) async {
    await Settings.setInt(
      '${scene.prefix}auto_backup_last_at',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 是否到达自动备份时机：开启 且（从未备份过 或 距上次备份超过频率间隔）。
  static Future<bool> shouldRun(AutoBackupScene scene) async {
    if (!await isEnabled(scene)) return false;
    final lastAt = await Settings.getInt('${scene.prefix}auto_backup_last_at');
    if (lastAt == null) return true;
    final f = await frequency(scene);
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastAt;
    return elapsed >= f.hours * 3600000;
  }

  /// 对指定场景执行一次自动备份；成功记录执行时间，失败仅返错误信息。
  static Future<String?> runOnce(AutoBackupScene scene) async {
    if (!await shouldRun(scene)) return null;
    final error = await (scene == AutoBackupScene.webdav
        ? _runWebdavBackup()
        : _runLocalBackup());
    if (error == null) await markDone(scene);
    return error;
  }

  /// app 启动时对全部已启用场景执行一次到期检测。
  static Future<void> runAll() async {
    await runOnce(AutoBackupScene.webdav);
    await runOnce(AutoBackupScene.local);
  }

  static Future<String?> _runWebdavBackup() async {
    try {
      final config = await loadWebDavConfig();
      if (config == null) return 'WebDAV 未配置';
      final service = WebDavService(
        server: config.server,
        username: config.username,
        password: config.password,
        directory: config.directory,
      );
      final tmpDir = await Directory.systemTemp.createTemp('sr_autobackup');
      try {
        final localPath = await createSrbBackup(dir: tmpDir);
        final name = localPath.split(Platform.pathSeparator).last;
        await service.upload(localPath, name);
      } finally {
        if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> _runLocalBackup() async {
    try {
      await createSrbBackup();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
