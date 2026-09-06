/// WebDAV 备份配置（服务器/账号/密码/目录）。
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

  bool get isValid =>
      server.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty &&
      directory.trim().isNotEmpty;
}

/// WebDAV 远端备份文件元信息。
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
