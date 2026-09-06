import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../models/webdav_config.dart';
import 'settings.dart';

const _keyServer = 'webdav_server';
const _keyUsername = 'webdav_username';
const _keyPassword = 'webdav_password';
const _keyDirectory = 'webdav_directory';

/// 读取持久化的 WebDAV 配置；未填服务器时返回 null。
Future<WebDavConfig?> loadWebDavConfig() async {
  final server = await Settings.getString(_keyServer) ?? '';
  if (server.trim().isEmpty) return null;
  return WebDavConfig(
    server: server,
    username: await Settings.getString(_keyUsername) ?? '',
    password: await Settings.getString(_keyPassword) ?? '',
    directory: await Settings.getString(_keyDirectory) ?? '',
  );
}

/// 保存 WebDAV 配置（一次批量写入落盘）。
Future<void> saveWebDavConfig(WebDavConfig config) async {
  await Settings.setStrings({
    _keyServer: config.server.trim(),
    _keyUsername: config.username.trim(),
    _keyPassword: config.password,
    _keyDirectory: config.directory.trim(),
  });
}

/// WebDAV 远端备份操作（列目录/上传/下载/删除）。
class WebDavService {
  final String server;
  final String username;
  final String password;
  final String directory;

  WebDavService({
    required this.server,
    required this.username,
    required this.password,
    this.directory = '',
  });

  /// 远程目录相对路径（去首尾 /）。
  String get _dirPath => directory.trim().replaceAll(RegExp(r'^/+|/+$'), '');

  /// 拼接目录与文件名，得到相对服务器根路径。
  String _remotePath(String name) {
    final dir = _dirPath;
    return dir.isEmpty ? name : '$dir/$name';
  }

  /// 创建 WebDAV 客户端：15s 连接超时、30s 读写超时、信任自签名证书。
  webdav.Client _client() {
    final client = webdav.newClient(
      server.trim(),
      user: username,
      password: password,
    );
    client.setConnectTimeout(15000);
    client.setSendTimeout(30000);
    client.setReceiveTimeout(30000);
    client.c.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final http = HttpClient();
        http.badCertificateCallback = (_, _, _) => true;
        return http;
      },
    );
    return client;
  }

  /// 列出服务器备份目录下的 .srb 文件。
  Future<List<WebDavFile>> listBackups() async {
    final client = _client();
    try {
      final files = await client.readDir(_dirPath);
      return files
          .where((f) => (f.isDir ?? false) == false)
          .where((f) => (f.name ?? '').endsWith('.srb'))
          .map(
            (f) => WebDavFile(
              name: f.name ?? '',
              path: f.path ?? '',
              size: f.size ?? 0,
              modified: f.mTime,
            ),
          )
          .toList();
    } on DioException catch (e) {
      throw HttpException(_statusError('列目录', e));
    } finally {
      client.c.close(force: true);
    }
  }

  /// 上传本地文件到 WebDAV 服务器（流式）。
  Future<void> upload(String localPath, String remoteName) async {
    final client = _client();
    try {
      await client.writeFromFile(localPath, _remotePath(remoteName));
    } on DioException catch (e) {
      throw HttpException(_statusError('上传', e));
    } finally {
      client.c.close(force: true);
    }
  }

  /// 从 WebDAV 下载文件到本地临时路径，返回保存路径。
  Future<String> download(String remoteName) async {
    final client = _client();
    final tmpDir = await Directory.systemTemp.createTemp('sr_webdav');
    try {
      final tmp = File(p.join(tmpDir.path, p.basename(remoteName)));
      await client.read2File(_remotePath(remoteName), tmp.path);
      return tmp.path;
    } on DioException catch (e) {
      throw HttpException(_statusError('下载', e));
    } finally {
      client.c.close(force: true);
    }
  }

  /// 删除 WebDAV 上的备份文件。
  Future<void> delete(String remoteName) async {
    final client = _client();
    try {
      await client.remove(_remotePath(remoteName));
    } on DioException catch (e) {
      throw HttpException(_statusError('删除', e));
    } finally {
      client.c.close(force: true);
    }
  }

  String _statusError(String action, DioException e) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) {
      return '$action失败（HTTP $code）：认证被拒绝，请确认用户名密码正确'
          '（坚果云需在官网生成「应用密码」，不能使用登录密码）';
    }
    if (code == 404) {
      return '$action失败（HTTP 404）：远程目录不存在，请检查远程目录路径';
    }
    if (code == 405 || code == 501) {
      return '$action失败（HTTP $code）：服务器不支持 WebDAV，请确认服务器地址正确';
    }
    return '$action失败：${e.message}';
  }
}
