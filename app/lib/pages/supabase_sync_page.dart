import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/author_service.dart';
import '../models/cloud_config.dart';
import '../services/cloud_config.dart';
import '../services/record_service.dart';
import '../services/settings.dart';
import '../services/sync_service.dart';
import '../services/theme_service.dart';
import '../utils/log.dart';
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
  String? _lastNickname;
  String _authorId = '';
  String _avatarUrl = '';
  bool _loading = true;

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
    final authorId = await AuthorService.instance.existingAuthorId();
    final avatar = await AuthorService.instance.ownAvatar();
    if (!mounted) return;
    _nicknameController.text = nickname;
    _lastNickname = nickname.trim();
    _urlController.text = config.supabaseUrl;
    _keyController.text = config.supabaseAnonKey;
    _authorId = authorId ?? '';
    _avatarUrl = avatar ?? '';
    setState(() => _loading = false);
    // 未保存过连接配置时进入页面即弹出填写弹窗；已有配置则不再打扰。
    final hasConfig =
        config.supabaseUrl.trim().isNotEmpty &&
        config.supabaseAnonKey.trim().isNotEmpty;
    if (!hasConfig) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onSyncTap();
      });
    }
  }

  /// 点击「同步」后先弹窗填写 URL 与 key，确认后保存配置并重建连接。
  void _onSyncTap() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                labelText: 'Public KEY',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final url = _urlController.text.trim();
              final key = _keyController.text.trim();
              if (url.isEmpty || key.isEmpty) {
                showToast(context, '请完整填写项目地址和密钥');
                return;
              }
              Navigator.pop(dialogContext);
              showToast(context, '正在连接…');
              _connect(url, key);
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  Future<void> _connect(String url, String key) async {
    await saveCloudConfig(CloudConfig(supabaseUrl: url, supabaseAnonKey: key));
    bool ok;
    try {
      ok = await SyncService.instance.reconfigure();
    } catch (e) {
      appLog('[sync] reconfigure failed: $e');
      ok = false;
    }
    if (!mounted) return;
    showToast(context, ok ? '云端连接成功' : '云端连接未就绪，请检查项目地址和密钥');
    // 连接成功后：尚无用户ID则让用户选择身份（生成新ID / 使用旧ID）。
    if (ok && _authorId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showIdentityDialog();
      });
    }
  }

  /// 无用户ID时弹身份选择：生成新ID / 使用旧ID。
  void _showIdentityDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('设置身份'),
        content: const Text('你是新用户还是老用户？'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final id = await AuthorService.instance.createNewAuthorId();
              if (!mounted) return;
              setState(() {
                _authorId = id;
                _nicknameController.text = '';
                _lastNickname = '';
                _avatarUrl = '';
              });
              showToast(context, '已生成新的用户ID');
            },
            child: const Text('生成新ID'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (!mounted) return;
              _showOldIdDialog();
            },
            child: const Text('使用旧ID'),
          ),
        ],
      ),
    );
  }

  /// 用旧设备 author_id 从云端恢复身份（换设备 / 使用旧ID）。
  void _showOldIdDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('使用旧设备用户ID'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '粘贴旧用户ID',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final id = controller.text.trim();
              if (id.isEmpty) {
                showToast(context, '请输入旧设备的用户ID');
                return;
              }
              Navigator.pop(dialogContext);
              await _applyOldId(id);
            },
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }

  /// 用旧 author_id 从云端拉昵称/头像写回本机。
  Future<void> _applyOldId(String id) async {
    final nickname = await AuthorService.instance.restoreNickname(id);
    if (!mounted) return;
    if (nickname == null) {
      showToast(context, '未找到该ID的昵称，请检查连接后重试');
      return;
    }
    final avatar = await AuthorService.instance.restoreAvatar(id);
    if (!mounted) return;
    setState(() {
      _authorId = id;
      _nicknameController.text = nickname;
      _lastNickname = nickname;
      _avatarUrl = avatar ?? '';
    });
    showToast(context, '已恢复到昵称：$nickname');
  }

  /// 编辑昵称：弹窗输入（样式对齐新增/编辑账本弹窗）。
  void _showNicknameDialog() {
    final controller = TextEditingController(text: _nicknameController.text);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(
          spacingXL,
          spacingXL,
          spacingXL,
          spacingS,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          spacingL,
          0,
          spacingL,
          spacingS,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          inputFormatters: [LengthLimitingTextInputFormatter(6)],
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.transparent),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).extension<AppThemeColors>()!.primary,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _nicknameController.text = controller.text;
              setState(() {});
              _onNicknameChanged(controller.text);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _onNicknameChanged(String value) {
    final t = value.trim();
    _lastNickname = persistIfChanged(t, _lastNickname, (v) {
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
    await SyncService.instance.enqueueProfileChange(
      authorId: authorId,
      nickname: nickname,
    );
  }

  /// 选头像（相册/拍照）→ 上传 → 更新本机 + 云端 + 广播。
  Future<void> _pickAvatar(ImageSource source) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source);
    } catch (e) {
      appLog('[avatar] pickImage failed: $e');
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
      final tmp = File(
        '${Directory.systemTemp.path}/avatar_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      await tmp.writeAsBytes(
        await File(picked.path).readAsBytes(),
        flush: true,
      );
      tmpPath = tmp.path;
    } catch (e) {
      appLog('[avatar] copy failed: $e');
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
    await SyncService.instance.enqueueProfileChange(
      authorId: authorId,
      avatarUrl: url,
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
        title: 'Supabase 同步',
        actions: [
          IconButton(
            onPressed: _onSyncTap,
            icon: SvgPicture.asset(
              'assets/icons/supabase.svg',
              width: 22,
              height: 22,
              colorFilter: const ColorFilter.mode(
                colorTextOnPrimary,
                BlendMode.srcIn,
              ),
            ),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: spacingXS),
                  Center(
                    child: GestureDetector(
                      onTap: _showAvatarPicker,
                      child: _avatarUrl.isNotEmpty
                          ? AuthorAvatar(url: _avatarUrl, size: 64)
                          : AuthorAvatar(url: null, size: 64),
                    ),
                  ),
                  const SizedBox(height: spacingM),
                  Container(
                    decoration: BoxDecoration(
                      color: colorBackgroundCard,
                      borderRadius: BorderRadius.circular(radiusMedium),
                    ),
                    child: GestureDetector(
                      onTap: _showNicknameDialog,
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        height: heightOptionBar,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: spacingL,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '昵称',
                                  style: textListItem.copyWith(
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              if (_nicknameController.text.isNotEmpty)
                                Text(
                                  _nicknameController.text,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.black,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right,
                                size: iconSizeDefault,
                                color: colorTextSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
