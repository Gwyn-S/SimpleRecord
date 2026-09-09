/// 云同步配置：Supabase 项目地址与匿名密钥，构建时注入（--dart-define-from-file），
/// 用户无需手动填写。
class CloudConfig {
  final String supabaseUrl;
  final String supabaseAnonKey;

  const CloudConfig({this.supabaseUrl = '', this.supabaseAnonKey = ''});

  bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;
}