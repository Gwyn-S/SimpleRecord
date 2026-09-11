import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../utils/formatters.dart';
import '../../services/cloud/auto_backup_service.dart';
import '../../services/cloud/srb_backup_service.dart';
import '../../services/core/theme_service.dart';
import '../../models/cloud/webdav_config.dart';
import '../../services/cloud/webdav_service.dart';
import '../../utils/toast.dart';
import '../../widgets/cloud/auto_backup_tile.dart';
import '../../widgets/common/busy_dialog.dart';
import '../../widgets/common/common_app_bar.dart';

class WebDavPage extends StatefulWidget {
  const WebDavPage({super.key});

  @override
  State<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends State<WebDavPage> {
  WebDavConfig? _config;
  List<WebDavFile> _files = [];
  bool _busy = false;
  String? _error;
  bool _dialogOpen = false;
  bool _connecting = false;

  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _directoryController = TextEditingController();
  bool _showPassword = false;
  bool _operating = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _directoryController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final config = await loadWebDavConfig();
    if (!mounted) return;
    _serverController.text = config?.server ?? '';
    _usernameController.text = config?.username ?? '';
    _passwordController.text = config?.password ?? '';
    _directoryController.text = config?.directory ?? '';
    if (config == null) {
      _showConfigDialog();
      return;
    }
    // 已有配置：尝试连通，成功直接进；失败则锁死弹窗修改配置。
    try {
      final service = WebDavService(
        server: config.server,
        username: config.username,
        password: config.password,
        directory: config.directory,
      );
      final files = await service.listBackups();
      if (!mounted) return;
      setState(() {
        _config = config;
        _files = files;
      });
    } catch (e) {
      if (!mounted) return;
      _showConfigDialog();
    }
  }

  /// 模态配置弹窗：未真正连通前锁死，验证通过才进入列表页。
  void _showConfigDialog() {
    if (_dialogOpen) return;
    _dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _serverController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: spacingM),
              TextField(
                controller: _directoryController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '远程目录',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: spacingM),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: spacingM),
              TextField(
                controller: _passwordController,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: '密码',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: iconSizeDefault,
                    ),
                    onPressed: () =>
                        setDialogState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
              if (_connecting) ...[
                const SizedBox(height: spacingM),
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          actions: [
            OutlinedButton(
              onPressed: _connecting
                  ? null
                  : () {
                      Navigator.pop(dialogContext);
                      if (mounted && _config == null) Navigator.pop(context);
                    },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _connecting
                  ? null
                  : () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      _verifyAndEnter(dialogContext);
                    },
              child: const Text('连接'),
            ),
          ],
        ),
      ),
    ).then((_) => _dialogOpen = false);
  }

  Future<void> _verifyAndEnter(BuildContext dialogContext) async {
    final config = WebDavConfig(
      server: _serverController.text.trim(),
      username: _usernameController.text,
      password: _passwordController.text,
      directory: _directoryController.text.trim(),
    );
    if (!config.isValid) {
      showToast(context, '请填写完整配置');
      return;
    }
    final service = WebDavService(
      server: config.server,
      username: config.username,
      password: config.password,
      directory: config.directory,
    );
    // 阻断式加载：弹全局转圈，避免连接期间重复点击/无反馈。
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => busyDialog('连接中'),
    );
    _connecting = true;
    try {
      final files = await service.listBackups();
      await saveWebDavConfig(config);
      if (!mounted) return;
      navigator.pop();
      _connecting = false;
      _showPassword = false;
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      setState(() {
        _config = config;
        _files = files;
      });
      showToast(context, '连接成功');
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      _connecting = false;
      showToast(context, '连接失败，请检查配置与网络');
    }
  }


  Future<void> _refresh(WebDavConfig config, {bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final service = WebDavService(
        server: config.server,
        username: config.username,
        password: config.password,
        directory: config.directory,
      );
      final files = await service.listBackups();
      if (!mounted) return;
      setState(() {
        _files = files;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _uploadBackup() async {
    if (_operating) return;
    setState(() => _operating = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => busyDialog('上传中'),
    );
    final tmpDir = await Directory.systemTemp.createTemp('sr_upload');
    try {
      final localPath = await createSrbBackup(dir: tmpDir);
      final name = localPath.split(Platform.pathSeparator).last;
      final service = WebDavService(
        server: _config!.server,
        username: _config!.username,
        password: _config!.password,
        directory: _config!.directory,
      );
      await service.upload(localPath, name);
      if (!mounted) return;
      navigator.pop();
      setState(() => _operating = false);
      showToast(context, '上传成功');
      await _refresh(_config!, silent: true);
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      setState(() => _operating = false);
      showToast(context, '上传失败：$e');
    } finally {
      try {
        if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _downloadRestore(WebDavFile file) async {
    if (_operating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复备份'),
        content: const Text('将从云端下载此备份并覆盖当前全部数据，且不可撤销。确定恢复吗？'),
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
    if (confirmed != true || !mounted) return;
    setState(() => _operating = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => busyDialog('恢复中'),
    );
    String? localPath;
    try {
      final service = WebDavService(
        server: _config!.server,
        username: _config!.username,
        password: _config!.password,
        directory: _config!.directory,
      );
      localPath = await service.download(file.name);
      await restoreSrbBackup(localPath);
      if (!mounted) return;
      navigator.pop();
      setState(() => _operating = false);
      showToast(context, '恢复成功');
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      setState(() => _operating = false);
      showToast(context, '恢复失败：$e');
    } finally {
      if (localPath != null) {
        try {
          final dir = Directory(p.dirname(localPath));
          if (dir.existsSync()) await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> _deleteFile(WebDavFile file) async {
    if (_operating) return;
    setState(() => _operating = true);
    try {
      final service = WebDavService(
        server: _config!.server,
        username: _config!.username,
        password: _config!.password,
        directory: _config!.directory,
      );
      await service.delete(file.name);
      if (!mounted) return;
      setState(() => _operating = false);
      showToast(context, '已删除');
      await _refresh(_config!, silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _operating = false);
      showToast(context, '删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
        title: 'WebDAV 备份',
        actions: [
          IconButton(
            onPressed: _busy ? null : _showConfigDialog,
            icon: const Icon(Icons.dns_outlined),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: colorTextOnPrimary.withValues(alpha: 0.3),
            height: 1,
          ),
        ),
      ),
      body: _config == null
          ? const SizedBox.shrink()
          : _buildCloud(),
    );
  }

  Widget _buildCloud() {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(spacingL, spacingL, spacingL, 0),
          child: Row(
            children: [
              const Expanded(
                child: SizedBox(
                  height: 44,
                  child: AutoBackupTile(scene: AutoBackupScene.webdav),
                ),
              ),
              const SizedBox(width: spacingM),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _operating ? null : _uploadBackup,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('立即上传'),
                    style: FilledButton.styleFrom(
                      backgroundColor: themeColor,
                      disabledBackgroundColor: themeColor,
                      disabledForegroundColor: colorTextOnPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: spacingXS),
        if (_busy && _files.isEmpty && _error == null)
          const Padding(
            padding: EdgeInsets.all(spacingXL),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(spacingXL),
            child: Column(
              children: [
                Text(
                  '连接失败：$_error',
                  style: textItemSub,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: spacingM),
                OutlinedButton(
                  onPressed: () => _refresh(_config!),
                  child: const Text('重试'),
                ),
              ],
            ),
          )
        else if (_files.isEmpty)
          const SizedBox.shrink()
        else
          Expanded(
            child: ListView.separated(
              itemCount: _files.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, thickness: 0.5, color: colorDivider),
              itemBuilder: (context, index) {
                final file = _files[index];
                return ListTile(
                  title: Text(file.name, style: textBody),
                  subtitle: Text(formatFileSize(file.size), style: textItemSub),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore, size: 20),
                        onPressed: () => _downloadRestore(file),
                        tooltip: '恢复',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: colorTextSecondary,
                        ),
                        onPressed: () => _deleteFile(file),
                        tooltip: '删除',
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
