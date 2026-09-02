/// 云同步配置：Supabase 项目地址与匿名密钥，来自用户在建项目后填写。
class CloudConfig {
  final String supabaseUrl;
  final String supabaseAnonKey;

  const CloudConfig({this.supabaseUrl = '', this.supabaseAnonKey = ''});

  bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  CloudConfig copyWith({String? supabaseUrl, String? supabaseAnonKey}) =>
      CloudConfig(
        supabaseUrl: supabaseUrl ?? this.supabaseUrl,
        supabaseAnonKey: supabaseAnonKey ?? this.supabaseAnonKey,
      );
}
