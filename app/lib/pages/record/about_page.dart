import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../services/core/theme_service.dart';
import '../../services/core/update_installer.dart';
import '../../services/core/update_service.dart';
import '../../utils/toast.dart';
import '../../widgets/common/busy_dialog.dart';
import '../../widgets/common/settings_item.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// 真机实际安装版本（发布时用 --build-name 覆盖也以安装后的值为准）。
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  Future<void> _checkUpdate(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => busyDialog('检查更新中'),
    );
    final latest = await UpdateService.instance.checkForUpdate();
    navigator.pop();
    if (!context.mounted) return;
    if (latest == null) {
      showToast(context, '检查更新失败，请稍后重试');
      return;
    }
    if (UpdateService.hasNewVersion(latest)) {
      await _showUpdateDialog(context, latest);
      return;
    }
    showToast(context, '已是最新版本');
  }

  Future<void> _showUpdateDialog(BuildContext context, UpdateInfo? latest) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: spacingXL, vertical: spacingXL),
        child: SizedBox(
          width: 320,
          height: 320,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              spacingXL,
              spacingXL,
              spacingXL,
              spacingM,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发现新版本 $_version -> '
                  '${UpdateService.latestLabel(latest)}',
                  style: textDialogTitle,
                ),
                const SizedBox(height: spacingM),
                Expanded(
                  child: SingleChildScrollView(child: _buildChangelog(latest)),
                ),
                const SizedBox(height: spacingM),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: spacingXS),
                    TextButton(
                      onPressed: () {
                        final update = latest;
                        Navigator.pop(dialogContext);
                        _proceedUpdate(context, update);
                      },
                      child: const Text('立即更新'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 有安装包(Android)走下载安装；否则(iOS 侧载/IPA)打开 GitHub Release 页。
  Future<void> _proceedUpdate(BuildContext context, UpdateInfo? update) async {
    final url = update?.assetUrl;
    if (url == null || url.isEmpty) {
      await _openReleasePage(context, update);
      return;
    }
    await _downloadAndInstall(context, update!, url);
  }

  Future<void> _openReleasePage(BuildContext context, UpdateInfo? update) async {
    final page = update?.releaseUrl ??
        'https://github.com/Gwyn-S/SimpleRecord/releases';
    try {
      final ok = await launchUrl(
        Uri.parse(page),
        mode: LaunchMode.externalApplication,
      );
      if (!context.mounted) return;
      if (!ok) showToast(context, '无法打开下载页');
    } catch (_) {
      if (!context.mounted) return;
      showToast(context, '无法打开下载页');
    }
  }

  Future<void> _downloadAndInstall(
    BuildContext context,
    UpdateInfo update,
    String url,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, p, _) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(spacingXXL),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: p > 0 && p < 1 ? p : null,
                  ),
                ),
                const SizedBox(width: spacingL),
                Text(
                  '正在下载更新 ${(p * 100).toStringAsFixed(0)}%',
                  style: textBody,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final file = await UpdateInstaller.instance.download(
      url,
      update.version,
      onProgress: (received, total) {
        progress.value = total > 0 ? received / total : 0;
      },
    );
    navigator.pop();
    if (!context.mounted) return;
    if (file == null) {
      showToast(context, '下载失败，请重试');
      return;
    }
    final allowInstall = await _confirmInstall(context, update);
    if (allowInstall != true || !context.mounted) return;
    final opened = await UpdateInstaller.instance.openApk(file.path);
    if (!context.mounted) return;
    if (!opened) showToast(context, '无法打开安装器，请到下载页手动安装');
  }

  /// 下载完成后的安装确认。
  Future<bool> _confirmInstall(BuildContext context, UpdateInfo update) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text('v${update.version} 安装包已下载完成，是否立即安装？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('安装'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Widget _buildChangelog(UpdateInfo? latest) {
    final log = latest?.changelog ?? '';
    if (log.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('v${UpdateService.latestLabel(latest)} 更新内容', style: textBody),
        const SizedBox(height: spacingXS),
        for (final line in log.split('\n'))
          if (line.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('· ${line.trim()}', style: textHint),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorBackgroundPage,
      appBar: AppBar(
        title: const Text('关于简记'),
        backgroundColor: Theme.of(context).extension<AppThemeColors>()!.primary,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          SettingsItem(
            title: '检查更新',
            trailing: Text(
              _version.isEmpty ? '' : 'V$_version',
              style: textHint,
            ),
            onTap: () => _checkUpdate(context),
          ),
        ],
      ),
    );
  }
}