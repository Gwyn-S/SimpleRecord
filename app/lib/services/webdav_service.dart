import 'dart:convert';
import 'dart:io';

import 'settings.dart';

const _keyServer = 'webdav_server';
const _keyUsername = 'webdav_username';
const _keyPassword = 'webdav_password';
const _keyDirectory = 'webdav_directory';

class WebDavConfig {
  final String server;
  final String username;
  final String password;
  final String directory;

  const WebDavConfig({
    required this.server,
    required this.username,
    required this.password,
    this.directory = '',
  });

  bool get isValid => server.trim().isNotEmpty;
}

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

Future<void> saveWebDavConfig(WebDavConfig config) async {
  await Settings.setString(_keyServer, config.server.trim());
  await Settings.setString(_keyUsername, config.username.trim());
  await Settings.setString(_keyPassword, config.password);
  await Settings.setString(_keyDirectory, config.directory.trim());
}

class WebDavFile {
  final String name;
  final String path;
  final int size;
  final DateTime? modified;

  const WebDavFile({
    required this.name,
    required this.path,
    required this.size,
    this.modified,
  });
}

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

  Uri _uri(String? name) {
    var base = server.trim();
    if (!base.endsWith('/')) base = '$base/';
    final dir = directory.trim();
    if (dir.isNotEmpty) {
      base = '$base${dir.replaceAll(RegExp(r'^/+|/+$'), '')}/';
    }
    return Uri.parse(name == null ? base : '$base$name');
  }

  HttpClient _client() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    client.badCertificateCallback = (_, _, _) => true;
    return client;
  }

  void _auth(HttpClientRequest request) {
    if (username.isEmpty) return;
    final token = base64Encode(utf8.encode('$username:$password'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
  }

  /// 列出服务器备份目录下的 .srb 文件。
  Future<List<WebDavFile>> listBackups() async {
    final client = _client();
    try {
      final request =
          await client.openUrl('PROPFIND', _uri(null));
      _auth(request);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/xml');
      request.headers.set('Depth', '1');
      request.write(
          '<?xml version="1.0" encoding="utf-8"?>'
          '<d:propfind xmlns:d="DAV:">'
          '<d:prop><d:displayname/><d:getcontentlength/><d:getlastmodified/></d:prop>'
          '</d:propfind>');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_statusError('列目录', response.statusCode));
      }
      return _parsePropfind(body);
    } finally {
      client.close(force: true);
    }
  }

  /// 上传本地文件到 WebDAV 服务器。
  Future<void> upload(String localPath, String remoteName) async {
    final file = File(localPath);
    final bytes = await file.readAsBytes();
    final client = _client();
    try {
      final request = await client.openUrl('PUT', _uri(remoteName));
      _auth(request);
      request.headers.contentType = ContentType.binary;
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_statusError('上传', response.statusCode));
      }
    } finally {
      client.close(force: true);
    }
  }

  /// 从 WebDAV 下载文件到本地临时路径，返回保存路径。
  Future<String> download(String remoteName) async {
    final client = _client();
    try {
      final request = await client.getUrl(_uri(remoteName));
      _auth(request);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException(_statusError('下载', response.statusCode));
      }
      final tmpDir = await Directory.systemTemp.createTemp('sr_webdav');
      final tmp = File('${tmpDir.path}${Platform.pathSeparator}$remoteName');
      final sink = tmp.openWrite();
      await response.pipe(sink);
      await sink.close();
      return tmp.path;
    } finally {
      client.close(force: true);
    }
  }

  /// 删除 WebDAV 上的备份文件。
  Future<void> delete(String remoteName) async {
    final client = _client();
    try {
      final request = await client.openUrl('DELETE', _uri(remoteName));
      _auth(request);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_statusError('删除', response.statusCode));
      }
    } finally {
      client.close(force: true);
    }
  }

  String _statusError(String action, int code) {
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
    return '$action失败：HTTP $code';
  }

  List<WebDavFile> _parsePropfind(String body) {
    final files = <WebDavFile>[];
    final pref = r'[a-zA-Z0-9]*:';
    final responseRe = RegExp(
      r'<(?:' + pref + r')?response[\s>](.*?)</(?:' + pref + r')?response>',
      dotAll: true,
    );
    final hrefRe = RegExp(
      r'<(?:' + pref + r')?href>(.*?)</(?:' + pref + r')?href>',
      dotAll: true,
    );
    final sizeRe = RegExp(
      r'<(?:' + pref + r')?getcontentlength>(.*?)</(?:' + pref + r')?getcontentlength>',
      dotAll: true,
    );
    final modifiedRe = RegExp(
      r'<(?:' + pref + r')?getlastmodified>(.*?)</(?:' + pref + r')?getlastmodified>',
      dotAll: true,
    );
    for (final m in responseRe.allMatches(body)) {
      final block = m.group(1)!;
      final hrefMatch = hrefRe.firstMatch(block);
      if (hrefMatch == null) continue;
      var href = hrefMatch.group(1)!.trim();
      href = Uri.decodeComponent(href);
      final parts = href.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty) continue;
      final name = parts.last;
      if (!name.endsWith('.srb')) continue;
      final sizeMatch = sizeRe.firstMatch(block);
      final modifiedMatch = modifiedRe.firstMatch(block);
      files.add(WebDavFile(
        name: name,
        path: href,
        size: int.tryParse(sizeMatch?.group(1)?.trim() ?? '') ?? 0,
        modified: _parseHttpDate(modifiedMatch?.group(1)?.trim()),
      ));
    }
    return files;
  }

  DateTime? _parseHttpDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return HttpDate.parse(raw);
  }
}
