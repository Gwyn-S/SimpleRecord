import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../services/author_service.dart';
import '../services/cloud_config.dart';
import '../services/record_service.dart';
import '../services/settings.dart';
import '../services/sync_service.dart';
import '../utils/persist.dart';
import '../utils/toast.dart';
import '../widgets/author_avatar.dart';
import '../widgets/common_app_bar.dart';

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
  final _authorIdController = TextEditingController();
  String? _lastNickname;
  String? _lastUrl;
  String? _lastKey;
  String _authorId = '';
  String _avatarUrl = '';
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
    _authorIdController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final nickname = await Settings.getString('nickname') ?? '';
    final config = await loadCloudConfig();
    final authorId = await AuthorService.instance.ensureAuthorId();
    final avatar = await AuthorService.instance.ownAvatar();
    if (!mounted) return;
    _nicknameController.text = nickname;
    _lastNickname = nickname.trim();
    _urlController.text = config.supabaseUrl;
    _lastUrl = config.supabaseUrl;
    _keyController.text = config.supabaseAnonKey;
    _lastKey = config.supabaseAnonKey;
    _authorId = authorId;
    _avatarUrl = avatar ?? '';
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
      _broadcastNickname(v);
    });
  }

  /// 改昵称后：存云端 profiles + 向共享账本广播 profile 事件。
  void _broadcastNickname(String nickname) async {
    await AuthorService.instance.syncNicknameToCloud();
    final authorId = await AuthorService.instance.ensureAuthorId();
    if (nickname.isEmpty) return;
    await SyncService.instance
        .enqueueProfileChange(authorId: authorId, nickname: nickname);
  }

  /// 选头像（相册/拍照）→ 上传 → 更新本机 + 云端 + 广播。
  Future<void> _pickAvatar(ImageSource source) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source);
    } catch (e) {
      debugPrint('[avatar] pickImage failed: $e');
      if (mounted) showToast(context, '选择图片失败');
      return;
    }
    if (picked == null || !mounted) return;
    // 复制到系统临时目录，仅用于上传，避免污染记账 images 图库。
    final String tmpPath;
    try {
      final ext = picked.path.contains('.')
          ? picked.path.substring(picked.path.lastIndexOf('.'))
          : '';
      final tmp =
          File('${Directory.systemTemp.path}/avatar_${DateTime.now().millisecondsSinceEpoch}$ext');
      await tmp.writeAsBytes(await File(picked.path).readAsBytes(), flush: true);
      tmpPath = tmp.path;
    } catch (e) {
      debugPrint('[avatar] copy failed: $e');
      if (mounted) showToast(context, '读取图片失败');
      return;
    }
    final url = await AuthorService.instance.changeAvatar(tmpPath);
    // 上传完成即清理临时副本。
    try {
      final tmp = File(tmpPath);
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    if (!mounted) return;
    if (url == null) {
      showToast(context, '头像上传失败，请检查云端连接');
      return;
    }
    setState(() => _avatarUrl = url);
    final authorId = await AuthorService.instance.ensureAuthorId();
    await SyncService.instance
        .enqueueProfileChange(authorId: authorId, avatarUrl: url);
    // 触发各页面重新加载并反查最新头像，保证条目头像即时刷新。
    recordsVersion.value++;
    if (!mounted) return;
    showToast(context, '头像已更新');
  }

  void _showAvatarPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colorBackgroundCard,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAvatar(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 复制本机 author_id 到剪贴板（供换设备粘贴）。
  void _copyAuthorId() {
    Clipboard.setData(ClipboardData(text: _authorId));
    showToast(context, '已复制用户ID');
  }

  /// 用旧设备的 author_id 从云端恢复昵称（换设备）。
  Future<void> _restore() async {
    final id = _authorIdController.text.trim();
    if (id.isEmpty) {
      showToast(context, '请输入旧设备的用户ID');
      return;
    }
    final nickname = await AuthorService.instance.restoreNickname(id);
    if (!mounted) return;
    if (nickname == null) {
      showToast(context, '未找到该ID的昵称，请检查连接后重试');
      return;
    }
    final avatar = await AuthorService.instance.restoreAvatar(id);
    if (!mounted) return;
    _nicknameController.text = nickname;
    _lastNickname = nickname;
    _authorId = id;
    _avatarUrl = avatar ?? '';
    setState(() {});
    showToast(context, '已恢复到昵称：$nickname');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
        title: 'Supabase 同步',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: colorTextOnPrimary.withValues(alpha: 0.3),
            height: 1,
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
                  Center(
                    child: GestureDetector(
                      onTap: _showAvatarPicker,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          if (_avatarUrl.isNotEmpty)
                            AuthorAvatar(url: _avatarUrl, size: 64)
                          else
                            AuthorAvatar(url: null, size: 64),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: colorTextOnPrimary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                size: 14, color: colorTextSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: spacingM),
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
                  Container(
                    padding: const EdgeInsets.all(spacingM),
                    decoration: BoxDecoration(
                      color: colorIconLightBackground,
                      borderRadius: BorderRadius.circular(radiusMedium),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('我的用户ID',
                                  style: TextStyle(fontSize: 13)),
                            ),
                            GestureDetector(
                              onTap: _copyAuthorId,
                              child: const Text('复制',
                                  style: TextStyle(
                                      color: Colors.blue, fontSize: 13)),
                            ),
                          ],
                        ),
                        const SizedBox(height: spacingXS),
                        Text(_authorId,
                            style: TextStyle(
                                fontSize: 13, color: colorTextSecondary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(height: spacingM),
                  TextField(
                    controller: _authorIdController,
                    decoration: const InputDecoration(
                      labelText: '换设备恢复：粘贴旧用户ID',
                      border: OutlineInputBorder(),
                      helperText: '换设备后填旧设备的用户ID，即可恢复昵称',
                    ),
                    onSubmitted: (_) => _restore(),
                  ),
                  const SizedBox(height: spacingM),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: _restore,
                      child: const Text('恢复昵称'),
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