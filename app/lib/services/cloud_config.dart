import '../models/cloud_config.dart';
import 'settings.dart';
import '../utils/id.dart';

const _keyDeviceId = 'device_id';

/// 构建时注入的云端配置（官方推荐做法：--dart-define-from-file 注入，
/// 密件不入 Git）。发布/分发版本内置，用户无需手动填写；
/// 本地开发未注入时为空，云同步功能随之不可用。
const _envUrl = String.fromEnvironment('SUPABASE_URL');
const _envAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// 云端配置来源唯一：构建注入值。
Future<CloudConfig> loadCloudConfig() async => const CloudConfig(
  supabaseUrl: _envUrl,
  supabaseAnonKey: _envAnonKey,
);

/// 本机唯一标识：首次生成后持久化，上行打标、下行防回声用。
Future<String> getOrCreateDeviceId() async {
  final existing = await Settings.getString(_keyDeviceId);
  if (existing != null && existing.trim().isNotEmpty) return existing;
  final id = genId();
  await Settings.setString(_keyDeviceId, id);
  return id;
}
