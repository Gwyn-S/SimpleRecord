import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 应用基础目录。
/// Android 上为 /data/data/[package]/（去掉 app_flutter），
/// 其他平台使用 getApplicationSupportDirectory()。
Future<Directory> appBaseDirectory() async {
  if (Platform.isAndroid) {
    final support = await getApplicationSupportDirectory();
    // support.path = /data/data/<package>/app_flutter
    // 去掉 app_flutter 这一层
    final base = Directory(support.path.replaceFirst('/app_flutter', ''));
    if (!base.existsSync()) base.createSync(recursive: true);
    return base;
  }
  return getApplicationSupportDirectory();
}
