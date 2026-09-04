import 'dart:io';

import 'settings.dart';
import 'srb_backup_service.dart';
import 'webdav_service.dart';

/// 自动备份频率。
enum AutoBackupFrequency {
  daily('每天', 24),
  weekly('每周', 168),
  monthly('每月', 720);

  const AutoBackupFrequency(this.label, this.hours);

  /// 界面展示文案。
  final String label;

  /// 对应的小时间隔。
  final int hours;

  static AutoBackupFrequency fromName(String? name) {
    return AutoBackupFrequency.values.firstWhere(
      (f) => f.name == name,
      orElse: () => AutoBackupFrequency.daily,
    );
  }
}

/// 自动备份配置：开关、频率、上次执行时间均按场景（前缀）独立存储。
/// 场景前缀：webdav_（WebDAV 上传）、local_（本地备份）。
class AutoBackupService {
  AutoBackupService._();

  static bool _isWebdav(String prefix) => prefix == 'webdav_';

  static Future<bool> isEnabled(String prefix) async {
    return await Settings.getBool('${prefix}auto_backup_enabled') ?? false;
  }

  static Future<AutoBackupFrequency> frequency(String prefix) async {
    return AutoBackupFrequency.fromName(
      await Settings.getString('${prefix}auto_backup_frequency'),
    );
  }

  /// 保存开关与频率设置（仅写入给定非空项）。
  static Future<void> save(String prefix, {bool? enabled, AutoBackupFrequency? freq}) async {
    if (enabled != null) {
      await Settings.setBool('${prefix}auto_backup_enabled', enabled);
    }
    if (freq != null) {
      await Settings.setString('${prefix}auto_backup_frequency', freq.name);
    }
  }

  static Future<void> markDone(String prefix) async {
    await Settings.setInt(
      '${prefix}auto_backup_last_at',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 是否到达自动备份时机：开启 且（从未备份过 或 距上次备份超过频率间隔）。
  static Future<bool> shouldRun(String prefix) async {
    if (!await isEnabled(prefix)) return false;
    final lastAt = await Settings.getInt('${prefix}auto_backup_last_at');
    if (lastAt == null) return true;
    final f = await frequency(prefix);
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastAt;
    return elapsed >= f.hours * 3600000;
  }

  /// 对指定场景执行一次自动备份；成功记录执行时间，失败仅返错误信息。
  static Future<String?> runOnce(String prefix) async {
    if (!await shouldRun(prefix)) return null;
    final error = await (_isWebdav(prefix)
        ? _runWebdavBackup()
        : _runLocalBackup());
    if (error == null) await markDone(prefix);
    return error;
  }

  /// app 启动时对全部已启用场景执行一次到期检测。
  static Future<void> runAll() async {
    await runOnce('webdav_');
    await runOnce('local_');
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
