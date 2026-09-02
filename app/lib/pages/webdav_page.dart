import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../utils/formatters.dart';
import '../services/srb_backup_service.dart';
import '../services/theme_service.dart';
import '../models/webdav_config.dart';
import '../services/webdav_service.dart';
import '../utils/toast.dart';
import '../widgets/common_app_bar.dart';

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

  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _directoryController = TextEditingController();
  bool _showPassword = false;
  bool _operating = false;
  bool _uploading = false;

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
    setState(() => _config = config);
    if (config != null) await _refresh(config);
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

  /// 保存入口：不校验、可直接保存，仿 AI 页。
  Future<void> _save() async {
    final server = _serverController.text.trim();
    final username = _usernameController.text;
    final password = _passwordController.text;
    final directory = _directoryController.text.trim();
    if (server.isEmpty &&
        username.isEmpty &&
        password.isEmpty &&
        directory.isEmpty) {
      showToast(context, '配置为空');
      return;
    }
    await saveWebDavConfig(
      WebDavConfig(
        server: server,
        username: username,
        password: password,
        directory: directory,
      ),
    );
    if (!mounted) return;
    showToast(context, '配置已保存');
  }

  Future<void> _connect() async {
    final config = WebDavConfig(
      server: _serverController.text.trim(),
      username: _usernameController.text,
      password: _passwordController.text,
      directory: _directoryController.text.trim(),
    );
    if (!config.isValid) {
      showToast(context, '请填写服务器地址');
      return;
    }
    setState(() => _config = config);
    await _refresh(config);
  }

  Future<void> _uploadBackup() async {
    if (_operating) return;
    setState(() {
      _operating = true;
      _uploading = true;
    });
    showToast(context, '上传中…');
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
      setState(() {
        _operating = false;
        _uploading = false;
      });
      showToast(context, '上传成功');
      await _refresh(_config!, silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _operating = false;
        _uploading = false;
      });
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
    showToast(context, '恢复中…');
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
      setState(() => _operating = false);
      showToast(context, '恢复成功');
    } catch (e) {
      if (!mounted) return;
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: colorTextOnPrimary.withValues(alpha: 0.3),
            height: 1,
          ),
        ),
      ),
      body: _config == null ? _buildSettings() : _buildCloud(),
    );
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: spacingM),
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
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  size: iconSizeDefault,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          const SizedBox(height: spacingL),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _connect,
                    child: const Text('连接'),
                  ),
                ),
              ),
              const SizedBox(width: spacingM),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _operating ? null : _uploadBackup,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorTextOnPrimary,
                            ),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(_uploading ? '上传中' : '立即备份上传'),
                    style: FilledButton.styleFrom(
                      backgroundColor: themeColor,
                      disabledBackgroundColor: themeColor,
                      disabledForegroundColor: colorTextOnPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: spacingM),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _config = null);
                        },
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('设置'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: spacingXS),
        Text(
          '服务器：${_config!.server}',
          style: textItemSub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
