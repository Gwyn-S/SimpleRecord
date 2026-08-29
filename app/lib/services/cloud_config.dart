import 'settings.dart';
import '../utils/id.dart';

const _keySupabaseUrl = 'supabase_url';
const _keySupabaseAnonKey = 'supabase_anon_key';
const _keyDeviceId = 'device_id';
const _keyCachedUid = 'supabase_uid';

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

Future<CloudConfig> loadCloudConfig() async => CloudConfig(
      supabaseUrl: await Settings.getString(_keySupabaseUrl) ?? '',
      supabaseAnonKey: await Settings.getString(_keySupabaseAnonKey) ?? '',
    );

Future<CloudConfig> saveCloudConfig(CloudConfig config) async {
  await Settings.setString(_keySupabaseUrl, config.supabaseUrl.trim());
  await Settings.setString(_keySupabaseAnonKey, config.supabaseAnonKey.trim());
  return config;
}

/// 本机唯一标识：首次生成后持久化，上行打标、下行防回声用。
Future<String> getOrCreateDeviceId() async {
  final existing = await Settings.getString(_keyDeviceId);
  if (existing != null && existing.trim().isNotEmpty) return existing;
  final id = genId();
  await Settings.setString(_keyDeviceId, id);
  return id;
}

/// 缓存最近一次登录到的云端用户 id，用于启动时判断是否可安全重连。
Future<String?> getCachedUid() => Settings.getString(_keyCachedUid);

Future<void> setCachedUid(String? uid) async {
  if (uid == null) {
    await Settings.remove(_keyCachedUid);
  } else {
    await Settings.setString(_keyCachedUid, uid);
  }
}