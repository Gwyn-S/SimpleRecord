import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../utils/toast.dart';
import 'local_backup_page.dart';
import 'webdav_page.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          title: const Text('备份'),
          backgroundColor: themeColor,
          foregroundColor: colorTextOnPrimary,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              color: colorTextOnPrimary.withValues(alpha: 0.3),
              height: 1,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '',
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: ListView(
        children: [
          _buildItem(
            context,
            icon: Icons.backup_outlined,
            title: '本地备份与导出',
            subtitle: '备份到本地，支持导出表格文件',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LocalBackupPage()),
            ),
          ),
          _buildItem(
            context,
            icon: Icons.cloud_outlined,
            title: 'WebDAV 备份',
            subtitle: '同步备份到 WebDAV 服务器',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebDavPage()),
            ),
          ),
          _buildItem(
            context,
            icon: Icons.cloud_sync_outlined,
            title: 'Supabase 同步',
            subtitle: '云端账户多端同步',
            onTap: () => showToast(context, 'Supabase 同步敬请期待'),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: 10),
        child: Row(
          children: [
            Container(
              width: sizeIconContainer,
              height: sizeIconContainer,
              decoration: BoxDecoration(
                color: themeColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: iconSizeXLarge, color: colorTextOnPrimary),
            ),
            const SizedBox(width: spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textListItem.copyWith(color: themeColor)),
                  Text(subtitle, style: textItemSub),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: iconSizeDefault, color: colorTextSecondary),
          ],
        ),
      ),
    );
  }
}
