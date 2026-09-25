import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

enum VaultAction { create, join }

/// 小金库入口弹层：选择「新建」或「加入」。
Future<VaultAction?> showVaultActionSheet(BuildContext context) {
  return showModalBottomSheet<VaultAction>(
    context: context,
    backgroundColor: colorBackgroundCard,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('新建小金库'),
            onTap: () => Navigator.pop(sheetContext, VaultAction.create),
          ),
          const Divider(height: 1, color: colorDivider),
          ListTile(
            title: const Text('加入小金库'),
            onTap: () => Navigator.pop(sheetContext, VaultAction.join),
          ),
        ],
      ),
    ),
  );
}