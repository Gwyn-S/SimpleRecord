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
import '../services/ledger_service.dart';
import '../services/settings.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../services/theme_service.dart';
import '../utils/log.dart';
import '../utils/toast.dart';
import '../widgets/author_avatar.dart';
import '../widgets/busy_dialog.dart';
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
  String _authorId = '';
  String _avatarUrl = '';
  bool _loading = true;
  bool _cloudReady = false;
  bool _dialogOpen = false;

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
    await AuthorService.instance.loadRecordAuthorDisplay();
    final nickname = await Settings.getString('nickname') ?? '';
    final config = await loadCloudConfig();
    final authorId = await AuthorService.instance.existingAuthorId();
    final avatar = await AuthorService.instance.ownAvatar();
    if (!mounted) return;
    _nicknameController.text = nickname;
    _urlController.text = config.supabaseUrl;
    _keyController.text = config.supabaseAnonKey;
    _authorId = authorId ?? '';
    _avatarUrl = avatar ?? '';
    setState(() => _loading = false);
    // 已保存配置则校验连通性解锁功能；未保存则弹配置弹窗（必填，锁住不进入）。
    final hasConfig =
        config.supabaseUrl.trim().isNotEmpty &&
        config.supabaseAnonKey.trim().isNotEmpty;
    if (hasConfig) {
      _verifyCloud();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onSyncTap();
      });
    }
  }

  /// 用已保存配置做连通性校验，成功才解锁功能。
  /// 已就绪且已登录则直接解锁；否则才重新建立连接验证（避免每次进页都重连）。
  Future<void> _verifyCloud() async {
    final mgr = SupabaseManager.instance;
    if (mgr.isReady && mgr.uid != null) {
      if (!mounted) return;
      setState(() => _cloudReady = true);
      return;
    }
    bool ok;
    try {
      ok = await SyncService.instance.reconfigure();
    } catch (e) {
      appLog('[sync] verify failed: $e');
      ok = false;
    }
    if (!mounted) return;
    setState(() => _cloudReady = ok);
    if (!ok) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onSyncTap();
      });
    }
  }

  /// 点击「同步」先弹窗填写 URL 与 key。未连通时模态锁死（不能点开别处、不能关），
  /// 连接成功才关闭并解锁。已有弹窗打开时不重复弹。
  void _onSyncTap() {
    if (_dialogOpen) return;
    _dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
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
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final url = _urlController.text.trim();
              final key = _keyController.text.trim();
              if (url.isEmpty || key.isEmpty) {
                showToast(context, '请填写配置');
                return;
              }
              Navigator.pop(dialogContext);
              await _connect(url, key);
              if (!mounted) return;
              if (!_cloudReady) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _onSyncTap();
                });
              }
            },
            child: const Text('连接'),
          ),
        ],
      ),
    ).whenComplete(() => _dialogOpen = false);
  }

  /// 校验 URL/KEY 连通性：阻塞转圈等待，成功后解锁。
  Future<bool> _connect(String url, String key) async {
    await saveCloudConfig(CloudConfig(supabaseUrl: url, supabaseAnonKey: key));
    if (!mounted) return false;
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => busyDialog('连接中'),
    );
    bool ok;
    try {
      ok = await SyncService.instance.reconfigure();
    } catch (e) {
      appLog('[sync] reconfigure failed: $e');
      ok = false;
    }
    if (!mounted) return ok;
    navigator.pop();
    if (ok) {
      setState(() => _cloudReady = true);
      showToast(context, '云端连接成功');
    } else {
      showToast(context, '云端连接失败，请检查配置');
    }
    return ok;
  }

  /// 记账条目作者显示偏好变更：持久化并刷新列表中条目展示。
  void _onRecordDisplayChanged(String value) async {
    await AuthorService.instance.setRecordAuthorDisplay(value);
    if (!mounted) return;
    setState(() {});
    recordsVersion.value++;
  }

  /// 开启同步 / 退出同步按钮。未登录则唤醒账号窗；已登录则登出回到未登录态。
  Future<void> _onSyncToggle() async {
    if (_authorId.isEmpty) {
      _showAccountDialog();
      return;
    }
    await AuthorService.instance.logout();
    if (!mounted) return;
    setState(() {
      _authorId = '';
      _nicknameController.text = '';
      _avatarUrl = '';
    });
    // 退出后当前账本可能指向已隐藏的共享账本，重置为可见账本并刷新列表。
    await _refreshAfterIdentityChange();
    if (!mounted) return;
    showToast(context, '已退出同步');
  }

  /// 登录/注册/退出后：把当前账本收敛到当前账号可见的范围并触发界面刷新。
  Future<void> _refreshAfterIdentityChange() async {
    await ensureCurrentLedgerId();
    recordsVersion.value++;
  }

  /// 注册 / 登录共用账号输入弹窗：填账号后可选「注册」或「登录」。
  void _showAccountDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('注册或登录账号'),
        content: TextField(
          controller: controller,
          autofocus: true,
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
            onPressed: () {
              final id = controller.text.trim();
              if (id.isEmpty) {
                showToast(context, '请输入账号');
                return;
              }
              Navigator.pop(dialogContext);
              _register(id);
            },
            child: const Text('注册'),
          ),
          FilledButton(
            onPressed: () {
              final id = controller.text.trim();
              if (id.isEmpty) {
                showToast(context, '请输入账号');
                return;
              }
              Navigator.pop(dialogContext);
              _login(id);
            },
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }

  /// 注册：校验账号不重复后绑定本机。
  Future<void> _register(String id) async {
    final exists = await AuthorService.instance.accountExists(id);
    if (!mounted) return;
    if (exists == true) {
      showToast(context, '账号已注册，请登录');
      return;
    }
    final ok = await AuthorService.instance.registerAccount(id);
    if (!mounted) return;
    if (!ok) {
      showToast(context, '注册失败，请重试');
      return;
    }
    final nickname = await AuthorService.instance.ownNickname() ?? '';
    if (!mounted) return;
    setState(() {
      _authorId = id;
      _nicknameController.text = nickname;
      _avatarUrl = '';
    });
    await _refreshAfterIdentityChange();
    if (!mounted) return;
    showToast(context, '注册成功');
  }

  /// 登录：校验账号存在后拉回昵称/头像。
  Future<void> _login(String id) async {
    final exists = await AuthorService.instance.accountExists(id);
    if (!mounted) return;
    if (exists != true) {
      showToast(context, '该账号不存在，请先注册');
      return;
    }
    await AuthorService.instance.loginAccount(id);
    if (!mounted) return;
    final nickname = await AuthorService.instance.ownNickname() ?? '';
    final avatar = await AuthorService.instance.ownAvatar() ?? '';
    if (!mounted) return;
    setState(() {
      _authorId = id;
      _nicknameController.text = nickname;
      _avatarUrl = avatar;
    });
    await _refreshAfterIdentityChange();
    if (!mounted) return;
    showToast(context, '登录成功');
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
              final v = controller.text.trim();
              if (v.isEmpty) {
                showToast(context, '昵称不能为空');
                return;
              }
              // 输入未变化时不重复广播，仅关闭弹窗。
              // 基准取 _nicknameController.text（弹窗打开时的昵称）。
              if (v == _nicknameController.text.trim()) {
                Navigator.pop(dialogContext);
                return;
              }
              // 输入有变化：写本地昵称 + 同步云端 + 广播给共享账本成员。
              Settings.setString('nickname', v);
              _broadcastNickname(v);
              Navigator.pop(dialogContext);
              _nicknameController.text = v;
              setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 改昵称后：存云端 profiles + 向共享账本广播 profile 事件。
  void _broadcastNickname(String nickname) async {
    final saved = await AuthorService.instance.syncNicknameToCloud();
    if (!saved && mounted) {
      showToast(context, '昵称同步失败，请检查云端连接');
    }
    final authorId = await AuthorService.instance.existingAuthorId();
    if (authorId == null) return;
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
    // 选图完成，进入读图/上传/云端写入阶段：弹阻塞式进度弹窗，期间不可关闭。
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => busyDialog('头像上传中'),
    );
    try {
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
      final authorId = await AuthorService.instance.existingAuthorId();
      if (authorId == null) return;
      await SyncService.instance.enqueueProfileChange(
        authorId: authorId,
        avatarUrl: url,
      );
      // 触发各页面重新加载并反查最新头像，保证条目头像即时刷新。
      recordsVersion.value++;
      if (!mounted) return;
      showToast(context, '头像已更新');
    } finally {
      navigator.pop();
    }
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
              title: const Text('相册'),
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

  /// 身份区（账号/头像/昵称）。无 author_id 时不显示。
  List<Widget> _buildIdentitySection() {
    if (_authorId.isEmpty) return [];
    Widget row({
      required String label,
      required Widget? trailing,
      required VoidCallback onTap,
      bool showChevron = true,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: colorBackgroundCard,
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: heightOptionBar,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: spacingL),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: textListItem.copyWith(color: Colors.black),
                    ),
                  ),
                  ?trailing,
                  if (showChevron) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      size: iconSizeDefault,
                      color: colorTextSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return [
      row(
        label: '头像',
        onTap: _showAvatarPicker,
        showChevron: false,
        trailing: AuthorAvatar(
          url: _avatarUrl.isEmpty ? null : _avatarUrl,
          size: 32,
          cornerRadius: radiusXS,
        ),
      ),
      const SizedBox(height: spacingM),
      row(
        label: '昵称',
        onTap: _showNicknameDialog,
        showChevron: false,
        trailing: _nicknameController.text.isNotEmpty
            ? Text(
                _nicknameController.text,
                style: const TextStyle(fontSize: 16, color: Colors.black),
              )
            : null,
      ),
      const SizedBox(height: spacingM),
      row(
        label: '账号',
        onTap: () {},
        showChevron: false,
        trailing: Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              _authorId,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, color: Colors.black),
            ),
          ),
        ),
      ),
    ];
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
          : !_cloudReady
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._buildIdentitySection(),
                  if (_authorId.isNotEmpty) ...[
                    const SizedBox(height: spacingM),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: spacingL),
                      decoration: BoxDecoration(
                        color: colorBackgroundCard,
                        borderRadius: BorderRadius.circular(radiusMedium),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '显示',
                              style: textListItem.copyWith(color: Colors.black),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: '',
                            menuPadding: EdgeInsets.zero,
                            onSelected: _onRecordDisplayChanged,
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: AuthorService.recordDisplayNickname,
                                height: 32,
                                padding: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: spacingM,
                                  ),
                                  child: Text('昵称', style: textBody),
                                ),
                              ),
                              PopupMenuItem(
                                value: AuthorService.recordDisplayAvatar,
                                height: 32,
                                padding: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: spacingM,
                                  ),
                                  child: Text('头像', style: textBody),
                                ),
                              ),
                            ],
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  AuthorService.instance.recordAuthorDisplay ==
                                          AuthorService.recordDisplayAvatar
                                      ? '头像'
                                      : '昵称',
                                  style: textBody,
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: colorTextPrimary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: spacingM),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: spacingL),
                    child: SizedBox(
                      height: heightOptionBar,
                      child: OutlinedButton(
                        onPressed: _onSyncToggle,
                        child: Text(_authorId.isNotEmpty ? '退出同步' : '开启同步'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
