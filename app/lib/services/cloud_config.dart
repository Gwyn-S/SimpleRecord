import 'settings.dart';
import '../utils/id.dart';

const _keyDeviceId = 'device_id';

/// 本机唯一标识：首次生成后持久化，上行打标、下行防回声用。
Future<String> getOrCreateDeviceId() async {
  final existing = await Settings.getString(_keyDeviceId);
  if (existing != null && existing.trim().isNotEmpty) return existing;
  final id = genId();
  await Settings.setString(_keyDeviceId, id);
  return id;
}
