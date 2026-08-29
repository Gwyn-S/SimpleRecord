import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../services/cloud_config.dart';
import '../services/sync_service.dart';
import '../services/theme_service.dart';
import '../utils/toast.dart';

/// Supabase 云同步配置页：填写项目地址与 anon key，保存后重建连接。
class SupabaseSyncPage extends StatefulWidget {
  const SupabaseSyncPage({super.key});

  @override
  State<SupabaseSyncPage> createState() => _SupabaseSyncPageState();
}

class _SupabaseSyncPageState extends State<SupabaseSyncPage> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final config = await loadCloudConfig();
    if (!mounted) return;
    _urlController.text = config.supabaseUrl;
    _keyController.text = config.supabaseAnonKey;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    if (url.isEmpty || key.isEmpty) {
      showToast(context, '请完整填写项目地址和密钥');
      return;
    }
    setState(() => _saving = true);
    await saveCloudConfig(CloudConfig(supabaseUrl: url, supabaseAnonKey: key));
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
        ok ? '配置已保存，云端连接成功' : '配置已保存，但云端连接未就绪，请检查配置或网络');
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
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Project URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: spacingM),
                  TextField(
                    controller: _keyController,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      labelText: 'anon public key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: spacingL),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text('连接'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}