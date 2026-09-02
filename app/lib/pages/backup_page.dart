import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../widgets/common_app_bar.dart';
import 'local_backup_page.dart';
import 'supabase_sync_page.dart';
import 'webdav_page.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
        title: '备份',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: colorTextOnPrimary.withValues(alpha: 0.3),
            height: 1,
          ),
        ),
      ),
      body: ListView(
        children: [
          _buildItem(
            context,
            title: '本地备份与导出',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LocalBackupPage()),
            ),
          ),
          _buildItem(
            context,
            title: 'WebDAV 备份',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebDavPage()),
            ),
          ),
          _buildItem(
            context,
            title: 'Supabase 同步',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupabaseSyncPage()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: heightOptionBar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: spacingL),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: textListItem.copyWith(color: Colors.black),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: iconSizeDefault,
                color: colorTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
