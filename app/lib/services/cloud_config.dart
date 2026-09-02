import '../models/cloud_config.dart';
import 'settings.dart';
import '../utils/id.dart';

const _keySupabaseUrl = 'supabase_url';
const _keySupabaseAnonKey = 'supabase_anon_key';
const _keyDeviceId = 'device_id';
const _keyCachedUid = 'supabase_uid';

Future<CloudConfig> loadCloudConfig() async => CloudConfig(
  supabaseUrl: await Settings.getString(_keySupabaseUrl) ?? '',
  supabaseAnonKey: await Settings.getString(_keySupabaseAnonKey) ?? '',
);

Future<CloudConfig> saveCloudConfig(CloudConfig config) async {
  await Settings.setStrings({
    _keySupabaseUrl: config.supabaseUrl.trim(),
    _keySupabaseAnonKey: config.supabaseAnonKey.trim(),
  });
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
