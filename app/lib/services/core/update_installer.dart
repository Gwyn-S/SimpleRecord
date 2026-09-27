import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'github_mirror.dart';

/// 下载更新包并调起系统安装。
///
/// 仅 Android 使用：下载 APK 到应用目录，再交给系统安装器。
class UpdateInstaller {
  UpdateInstaller._();

  static final UpdateInstaller instance = UpdateInstaller._();

  static const _connectTimeout = Duration(seconds: 20);
  static const _receiveTimeout = Duration(seconds: 60);

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
    ),
  );

  /// 下载 [url] 的 APK 到应用目录。
  /// 同版本安装包已缓存（文件名为 `simplerecord-<version>.apk`）时直接复用不重下；
  /// 否则按镜像顺序逐个尝试，下载完整并通过校验后改名落地。任何失败都会清掉
  /// .part，不把坏包残留在磁盘。
  /// [onProgress] 回传 (已下载, 总大小)，总大小未知时为 0。
  Future<File?> download(
    String url,
    String version, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'updates'),
    );
    final file = File(p.join(dir.path, 'simplerecord-$version.apk'));
    try {
      await dir.create(recursive: true);
    } catch (_) {}
    if (_isValidApk(file)) return file;
    for (final candidate in GitHubMirror.candidates(url)) {
      final done = await _tryDownload(candidate, file, onProgress);
      if (done != null) return done;
    }
    return null;
  }

  Future<File?> _tryDownload(
    String url,
    File file,
    void Function(int received, int total)? onProgress,
  ) async {
    final part = File('${file.path}.part');
    try {
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
      await _dio.download(
        url,
        part.path,
        onReceiveProgress: (received, total) {
          if (onProgress != null) onProgress(received, total);
        },
      );
      if (!_isValidApk(part)) {
        _discardPart(part);
        return null;
      }
      part.renameSync(file.path);
      _pruneExcept(file);
      return file;
    } catch (_) {
      _discardPart(part);
      return null;
    }
  }

  void _discardPart(File part) {
    try {
      if (part.existsSync()) part.deleteSync();
    } catch (_) {}
  }

  /// 只保留 [keep],删除 updates 目录下其他缓存的安装包。
  void _pruneExcept(File keep) {
    try {
      final entries = keep.parent.listSync();
      for (final entry in entries) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        if (!name.startsWith('simplerecord-') || !name.endsWith('.apk')) {
          continue;
        }
        if (entry.path == keep.path) continue;
        try {
          entry.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 启动清理：删除 updates 目录下「版本 ≤ 当前安装版本」的安装包缓存。
  /// 已装过的版本不可能再被复用（未来更新永远是更高版本），删掉避免残留占空间；
  /// 版本高于当前安装版本（用户下载好还没装的）一律保留，下次检查更新直接复用缓存。
  /// 以真机实际安装版本（PackageInfo）为基准，冷启动调用一次即可：
  /// 一次磁盘列表，毫秒级，任何失败静默。
  static Future<void> cleanupInstalledApk() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = _parseVersion(info.version);
      if (current == null) return;
      final dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'updates'),
      );
      if (!dir.existsSync()) return;
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        if (!name.startsWith('simplerecord-') || !name.endsWith('.apk')) {
          continue;
        }
        final ver = _parseVersion(
          name.substring('simplerecord-'.length, name.length - '.apk'.length),
        );
        if (ver == null) continue;
        if (_fileNotNewerThanCurrent(ver, current)) {
          try {
            entry.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static List<int>? _parseVersion(String s) {
    final parts = s.split('.');
    if (parts.isEmpty) return null;
    final out = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null) return null;
      out.add(n);
    }
    return out;
  }

  /// 文件版本是否 ≤ 当前版本（是则删，因为不再可能被复用）。
  static bool _fileNotNewerThanCurrent(List<int> fileV, List<int> currentV) {
    final len = fileV.length > currentV.length ? fileV.length : currentV.length;
    for (var i = 0; i < len; i++) {
      final a = i < fileV.length ? fileV[i] : 0;
      final b = i < currentV.length ? currentV[i] : 0;
      if (a != b) return a < b;
    }
    return true;
  }

  /// APK 完整性校验：大小在合理范围内，且是 ZIP 格式(PK\x03\x04 魔数)。
  /// 拦下「空文件 / HTML 错误页 / 断流残包」，校验不过一律当失败重下。
  static const _minApkBytes = 5 * 1024 * 1024; // 5MB，真实 APK 不会更小
  static const _maxApkBytes = 200 * 1024 * 1024; // 200MB 上限

  bool _isValidApk(File f) {
    try {
      if (!f.existsSync()) return false;
      final len = f.lengthSync();
      if (len < _minApkBytes || len > _maxApkBytes) return false;
      final raf = f.openSync(mode: FileMode.read);
      try {
        final magic = raf.readSync(4);
        return magic.length == 4 &&
            magic[0] == 0x50 &&
            magic[1] == 0x4B &&
            magic[2] == 0x03 &&
            magic[3] == 0x04;
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  /// 调起系统安装器安装 APK，返回是否成功拉起。
  /// 优先走原生 FileProvider + ACTION_VIEW（自写 Kotlin 通道，production 稳定），
  /// 原生失败再回退 open_filex。
  Future<bool> openApk(String path) async {
    const channel = MethodChannel('com.simplerecord.jizhang/install');
    try {
      final ok =
          await channel.invokeMethod<bool>('installApk', {'filePath': path});
      if (ok == true) return true;
    } catch (_) {}
    try {
      final result = await OpenFilex.open(path);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }
}