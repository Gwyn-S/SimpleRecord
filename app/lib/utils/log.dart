import 'package:flutter/foundation.dart';

/// 仅非 release 构建输出日志；release 编译时整段被剪除。
void appLog(String message) {
  if (!kReleaseMode) debugPrint(message);
}
