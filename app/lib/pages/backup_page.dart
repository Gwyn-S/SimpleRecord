import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

// TODO: WebDAV 备份功能（Phase 5）
// - 设置页面：填写坚果云 WebDAV 地址、账号、专用密码
// - 备份按钮：导出全部数据为 JSON → 上传到坚果云
// - 恢复按钮：从坚果云下载 → 解析 → 导入数据库
class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份'), backgroundColor: colorBackgroundCard, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: '', onPressed: () => Navigator.pop(context))),
      body: const Center(child: Text('备份设置', style: TextStyle(color: colorTextPlaceholder))),
    );
  }
}
