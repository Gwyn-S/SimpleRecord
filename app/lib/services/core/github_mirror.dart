/// GitHub 访问加速：拼接镜像前缀，官方直连兜底。
class GitHubMirror {
  GitHubMirror._();

  static const List<String> prefixes = [
    'https://git.tangbai.cc/',
    'https://github.chenc.dev/',
    'https://gh-proxy.com/',
  ];

  /// 三个镜像在前，GitHub 官方在后。
  static List<String> candidates(String originalUrl) =>
      [...prefixes.map((p) => '$p$originalUrl'), originalUrl];
}