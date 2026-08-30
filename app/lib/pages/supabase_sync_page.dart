import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../services/cloud_config.dart';
import '../services/settings.dart';
import '../services/sync_service.dart';
import '../services/theme_service.dart';
import '../utils/persist.dart';
import '../utils/toast.dart';

/// Supabase 云同步配置页：填写项目地址与 anon key，保存后重建连接。
class SupabaseSyncPage extends StatefulWidget {
  const SupabaseSyncPage({super.key});

  @override
  State<SupabaseSyncPage> createState() => _SupabaseSyncPageState();
}

class _SupabaseSyncPageState extends State<SupabaseSyncPage> {
  final _nicknameController = TextEditingController();
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  String? _lastNickname;
  String? _lastUrl;
  String? _lastKey;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final nickname = await Settings.getString('nickname') ?? '';
    final config = await loadCloudConfig();
    if (!mounted) return;
    _nicknameController.text = nickname;
    _lastNickname = nickname.trim();
    _urlController.text = config.supabaseUrl;
    _lastUrl = config.supabaseUrl;
    _keyController.text = config.supabaseAnonKey;
    _lastKey = config.supabaseAnonKey;
    setState(() => _loading = false);
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    if (url.isEmpty || key.isEmpty) {
      showToast(context, '请完整填写项目地址和密钥');
      return;
    }
    setState(() => _saving = true);
    bool ok;
    try {
      ok = await SyncService.instance.reconfigure();
    } catch (e) {
      debugPrint('[sync] reconfigure failed: $e');
      ok = false;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showToast(context,
        ok ? '云端连接成功' : '云端连接未就绪，请检查项目地址和密钥');
  }

  /// 保存只做保存（URL/key 同时也已输入即存），不做校验。
  Future<void> _saveConfig() async {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    if (_nicknameController.text.trim().isEmpty) {
      showToast(context, '请先填写昵称');
      return;
    }
    await saveCloudConfig(CloudConfig(supabaseUrl: url, supabaseAnonKey: key));
    if (!mounted) return;
    showToast(context, '配置已保存');
  }

  /// URL 与 key 改动即保存（与昵称一致）。
  void _onConfigChanged() {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    _lastUrl = persistIfChanged(
        url, _lastUrl, (v) => saveCloudConfig(CloudConfig(supabaseUrl: v, supabaseAnonKey: key)));
    _lastKey = persistIfChanged(
        key, _lastKey, (v) => saveCloudConfig(CloudConfig(supabaseUrl: url, supabaseAnonKey: v)));
  }

  void _onNicknameChanged(String value) {
    final t = value.trim();
    _lastNickname = persistIfChanged(
        t, _lastNickname, (v) {
      if (v.isEmpty) {
        Settings.remove('nickname');
      } else {
        Settings.setString('nickname', v);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          title: const Text('Supabase 同步'),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: spacingXS),
                  TextField(
                    controller: _nicknameController,
                    inputFormatters: [LengthLimitingTextInputFormatter(6)],
                    onChanged: _onNicknameChanged,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: spacingM),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => _onConfigChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Project URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: spacingM),
                  TextField(
                    controller: _keyController,
                    keyboardType: TextInputType.text,
                    onChanged: (_) => _onConfigChanged(),
                    decoration: const InputDecoration(
                      labelText: 'anon public key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: spacingL),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: _saving ? null : _connect,
                            child: const Text('连接'),
                          ),
                        ),
                      ),
                      const SizedBox(width: spacingM),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: FilledButton(
                            onPressed: _saveConfig,
                            child: const Text('保存'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}