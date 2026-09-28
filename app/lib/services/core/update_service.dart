import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'github_mirror.dart';

/// 更新检查结果：远端最新版本信息（版本号 + 该版本的更新说明 + 下载入口）。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.changelog,
    this.releaseUrl,
    this.assetUrl,
  });

  final String version;
  final String changelog;

  /// GitHub Release 页面地址（浏览器打开/手动下载兜底）。
  final String? releaseUrl;

  /// 当前平台安装包直链：Android 为 APK；iOS 无自动安装，恒为 null。
  final String? assetUrl;

  bool get isEmpty => version.isEmpty;
}

/// 检查更新：读取 GitHub Releases 最新版，与本机版本对比。
///
/// 走公开仓库的 releases/latest 接口（免 token），返回的 tag_name 去掉
/// 'v' 前缀即版本号，body 即更新说明。接口不可用时返回 null，由调用方提示。
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  /// GitHub Releases 最新版接口（公开仓库免 token）。
  static const _releasesApi =
      'https://api.github.com/repos/Gwyn-S/SimpleRecord/releases/latest';

  static const _timeout = Duration(seconds: 10);

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
    ),
  );

  String _installedVersion = '';

  /// 本机实际安装的版本号，取自 PackageInfo（即 pubspec.yaml 的 version）。
  /// 全 App 唯一版本来源：关于页展示与更新判断都读这里。
  /// 未加载完成时为空串。
  String get installedVersion => _installedVersion;

  /// 启动时读取一次真实安装版本。
  Future<void> loadInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _installedVersion = info.version;
    } catch (_) {
      _installedVersion = '';
    }
  }

  /// 检查是否有新版本。
  /// 返回 null 表示检查失败（网络/后端未就绪）；否则返回最新版本信息，
  /// 由调用方据此决定弹窗还是 toast。
  Future<UpdateInfo?> checkForUpdate() async {
    return _fetchLatestRemote();
  }

  Future<UpdateInfo?> _fetchLatestRemote() async {
    for (final url in GitHubMirror.candidates(_releasesApi)) {
      final info = await _tryFetchLatest(url);
      if (info != null) return info;
    }
    return null;
  }

  Future<UpdateInfo?> _tryFetchLatest(String url) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          responseType: ResponseType.json,
        ),
      );
      final data = response.data;
      if (data == null) return null;
      final tag =
          (data['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '');
      final body = (data['body'] as String?)?.trim() ?? '';
      if (tag == null || tag.isEmpty) return null;
      final releaseUrl = data['html_url'] as String?;
      String? apkUrl;
      final assets = data['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;
          final name = (asset['name'] as String?) ?? '';
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String?;
            break;
          }
        }
      }
      return UpdateInfo(
        version: tag,
        changelog: body,
        releaseUrl: releaseUrl,
        assetUrl: Platform.isAndroid ? apkUrl : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// 判断远端版本是否比本机新。
  bool hasNewVersion(UpdateInfo? latest) {
    if (latest == null || latest.isEmpty) return false;
    if (_installedVersion.isEmpty) return false;
    return _compareVersion(latest.version, _installedVersion) > 0;
  }

  /// 版本号比较：'1.2.10' > '1.2.9'。忽略 build 号（+ 之后的部分）。
  static int _compareVersion(String a, String b) {
    final pa = _split(a);
    final pb = _split(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va < vb ? -1 : 1;
    }
    return 0;
  }

  static List<int> _split(String v) {
    final base = v.split('+').first.trim();
    return base
        .split('.')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList();
  }

  /// 供调用方读取最新的具体版本号（弹窗展示用）。
  static String latestLabel(UpdateInfo? latest) =>
      latest == null || latest.isEmpty ? '' : latest.version;
}