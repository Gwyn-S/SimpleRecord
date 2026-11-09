/// GitHub 访问加速：拼接镜像前缀，官方直连兜底。
///
/// 检查更新与下载安装包拆成两份候选列表：前者只发几十 KB 的 JSON 请求，
/// 看重往返延迟与成功率；后者是 21 MB 的长连接，看重吞吐与不中断。
/// 两类镜像几乎不重合——能代理 api.github.com 的往往下载慢，下载快的
/// 又只代理 github.com 文件，共用一份列表会互相拖累。
class GitHubMirror {
  GitHubMirror._();

  /// 检查更新专用，按「可靠性优先、速度其次」排序。
  static const List<String> _apiPrefixes = [
    // 曾整站暂停数日后恢复，最新实测 5/5 通过、122–420ms，暂居首位，
    // 但无稳定观察期，后续若再失效会自动切到下一候选。
    'https://git.tangbai.cc/',
    // 16/16 通过，224–1602ms，快且无失败。
    'https://github.chenc.dev/',
    // 16/16 通过，1086–3171ms，稳但偏慢。
    'https://tvv.tw/',
    // 12/16 通过，647–1011ms；近期连续全通，故排在慢节点之前。
    'https://github.cnxiaobai.com/',
    // 15/16 通过，380–3075ms；下载不稳，不进下载列表。
    'https://gh-proxy.com/',
    // 15/16 通过，偶发十余秒，作末位兜底。
    'https://gh-proxy.org/',
  ];

  /// 下载安装包专用，按完整包实测吞吐排序。
  static const List<String> _downloadPrefixes = [
    // 恢复后实测两轮完整 21 MB 包仅 1.15–1.49s（14–18 MB/s），远快于
    // 其余节点；稳定性未观察几天，仅凭速度排首位。
    'https://git.tangbai.cc/',
    // 以下四个只代理 github.com 文件（不支持 api.github.com），
    // 单个 21 MB 包约 5 秒。
    'https://ghproxy.sakuramoe.dev/',
    'https://gh.padao.fun/',
    'https://30006000.xyz/',
    'https://ghproxy.mirror.skybyte.me/',
    // 5/5 完整，10.3–39.2s。
    'https://gh-proxy.org/',
    // 5/5 完整，11.2–40.8s。
    'https://tvv.tw/',
    // 5/5 完整，5.5–84.5s；波动最大，但最快一次跑满 3.85 MB/s。
    'https://github.chenc.dev/',
  ];

  /// 检查更新的候选链接：镜像在前，GitHub 官方在后。
  static List<String> apiCandidates(String originalUrl) =>
      [..._apiPrefixes.map((p) => '$p$originalUrl'), originalUrl];

  /// 下载安装包的候选链接：镜像在前，GitHub 官方在后。
  static List<String> downloadCandidates(String originalUrl) =>
      [..._downloadPrefixes.map((p) => '$p$originalUrl'), originalUrl];
}
