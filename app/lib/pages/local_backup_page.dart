import 'dart:io';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/export_service.dart';
import '../utils/formatters.dart';
import '../services/srb_backup_service.dart';
import '../services/theme_service.dart';
import '../utils/toast.dart';
import '../widgets/auto_backup_tile.dart';
import '../widgets/common_app_bar.dart';

class LocalBackupPage extends StatefulWidget {
  const LocalBackupPage({super.key});

  @override
  State<LocalBackupPage> createState() => _LocalBackupPageState();
}

class _LocalBackupPageState extends State<LocalBackupPage> {
  List<File> _files = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final dir = await backupDirectory();
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.srb'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    if (!mounted) return;
    setState(() => _files = files);
  }

  Future<void> _doBackup() async {
    setState(() => _busy = true);
    showToast(context, '备份中…');
    try {
      await createSrbBackup();
      await _refresh();
      _toast('备份成功');
    } catch (e) {
      _toast('备份失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final path = await exportCsv();
      _toast('导出成功：$path');
    } catch (e) {
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRestore(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复备份'),
        content: const Text('将用备份覆盖当前全部数据，且不可撤销。确定恢复吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复', style: TextStyle(color: colorDelete)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _busy = true);
    showToast(context, '恢复中…');
    try {
      await restoreSrbBackup(file.path);
      _toast('恢复成功');
    } catch (e) {
      _toast('恢复失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doDelete(File file) async {
    try {
      await file.delete();
      await _refresh();
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    showToast(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
        title: '本地备份',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: colorTextOnPrimary.withValues(alpha: 0.3),
            height: 1,
          ),
        ),
      ),
body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(spacingL, spacingL, spacingL, 0),
            padding: const EdgeInsets.symmetric(vertical: spacingXS),
            decoration: BoxDecoration(
              color: colorBackgroundCard,
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
            child: const AutoBackupTile(prefix: 'local_'),
          ),
          const SizedBox(height: spacingXS),
          Padding(
            padding: const EdgeInsets.fromLTRB(spacingL, spacingL, spacingL, 0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _doBackup,
                      icon: const Icon(Icons.backup_outlined),
                      label: const Text('立即备份'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).extension<AppThemeColors>()!.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: spacingM),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _exportCsv,
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text('导出 CSV'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _files.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    itemCount: _files.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: colorDivider,
                    ),
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final name = file.path.split(Platform.pathSeparator).last;
                      return ListTile(
                        title: Text(name, style: textBody),
                        subtitle: Text(
                          formatFileSize(file.lengthSync()),
                          style: textItemSub,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore, size: 20),
                              onPressed: _busy ? null : () => _doRestore(file),
                              tooltip: '恢复',
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: colorTextSecondary,
                              ),
                              onPressed: () => _doDelete(file),
                              tooltip: '删除',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
