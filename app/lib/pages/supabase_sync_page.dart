import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/author_service.dart';
import '../services/record_service.dart';
import '../services/ledger_service.dart';
import '../services/settings.dart';
import '../services/sync_service.dart';
import '../services/theme_service.dart';
import '../utils/log.dart';
import '../utils/toast.dart';
import '../widgets/author_avatar.dart';
import '../widgets/busy_dialog.dart';
import '../widgets/common_app_bar.dart';

/// Supabase 云同步账号页：登录/注册、昵称与头像管理。
/// 项目地址与 anon key 由构建注入（--dart-define-from-file），无需用户填写。
class SupabaseSyncPage extends StatefulWidget {
  const SupabaseSyncPage({super.key});

  @override
  State<SupabaseSyncPage> createState() => _SupabaseSyncPageState();
}

class _SupabaseSyncPageState extends State<SupabaseSyncPage> {
  final _nicknameController = TextEditingController();
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
    super.dispose();
  }

  Future<void> _init() async {
    await AuthorService.instance.loadRecordAuthorDisplay();
    final nickname = await Settings.getString('nickname') ?? '';
    final authorId = await AuthorService.instance.existingAuthorId();
    final avatar = await AuthorService.instance.ownAvatar();
    if (!mounted) return;
    _nicknameController.text = nickname;
    _authorId = authorId ?? '';
    _avatarUrl = avatar ?? '';
    setState(() => _loading = false);
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
    // 先停引擎再登出：避免残留 outbox 用即将失效的会话继续推送。
    await SyncService.instance.stop();
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

  /// 注册 / 登录共用账号输入弹窗：填邮箱+密码后可选「注册」或「登录」。
  void _showAccountDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('注册或登录账号'),
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '邮箱',
                hintText: 'example@mail.com',
                border: InputBorder.none,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
              ),
            ),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: InputBorder.none,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              final email = emailController.text.trim();
              final password = passwordController.text;
              if (!_validateAccountInput(email, password)) return;
              Navigator.pop(dialogContext);
              _register(email, password);
            },
            child: const Text('注册'),
          ),
          FilledButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              final email = emailController.text.trim();
              final password = passwordController.text;
              if (!_validateAccountInput(email, password)) return;
              Navigator.pop(dialogContext);
              _login(email, password);
            },
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }

  /// 校验邮箱与密码格式，不合法时提示并返回 false。
  bool _validateAccountInput(String email, String password) {
    if (!email.contains('@')) {
      showToast(context, '请输入正确的邮箱');
      return false;
    }
    if (password.isEmpty) {
      showToast(context, '请输入密码');
      return false;
    }
    return true;
  }

  /// 注册：真实账号创建成功后绑定本机。
  Future<void> _register(String email, String password) async {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => busyDialog('注册中'),
    );
    final ok = await AuthorService.instance.registerAccount(email, password);
    if (!mounted) return;
    navigator.pop();
    if (!ok) {
      showToast(context, '注册失败，邮箱可能已被占用，请重试');
      return;
    }
    final nickname = await AuthorService.instance.ownNickname() ?? '';
    if (!mounted) return;
    setState(() {
      _authorId = email;
      _nicknameController.text = nickname;
      _avatarUrl = '';
    });
    await _refreshAfterIdentityChange();
    await SyncService.instance.start();
    if (!mounted) return;
    showToast(context, '注册成功');
  }

  /// 登录：真实账号校验通过后拉回昵称/头像。
  Future<void> _login(String email, String password) async {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => busyDialog('登录中'),
    );
    final ok = await AuthorService.instance.loginAccount(email, password);
    if (!mounted) return;
    navigator.pop();
    if (!ok) {
      showToast(context, '登录失败，请检查邮箱和密码');
      return;
    }
    final nickname = await AuthorService.instance.ownNickname() ?? '';
    final avatar = await AuthorService.instance.ownAvatar() ?? '';
    if (!mounted) return;
    setState(() {
      _authorId = email;
      _nicknameController.text = nickname;
      _avatarUrl = avatar;
    });
    await _refreshAfterIdentityChange();
    await SyncService.instance.start();
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
              FocusManager.instance.primaryFocus?.unfocus();
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
              _saveNicknameAndClose(dialogContext, v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 强一致保存昵称：先阻塞上传云端，成功才写本地并关弹窗。
  /// 失败提示且本地保持原值，避免"本地看似成功云端没有"的不一致。
  Future<void> _saveNicknameAndClose(
    BuildContext dialogContext,
    String nickname,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final oldNickname = _nicknameController.text.trim();
    // 先写本地供上传接口读取；只有上传成功才保留，失败回滚。
    Settings.setString('nickname', nickname);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => busyDialog('昵称同步中'),
    );
    final saved = await AuthorService.instance.syncNicknameToCloud();
    if (!mounted) return;
    navigator.pop();
    if (!saved) {
      // 回滚本地，展示保持旧昵称。
      Settings.setString('nickname', oldNickname);
      if (mounted) showToast(context, '昵称同步失败，请检查云端连接');
      return;
    }
    // 上传成功：广播给共享账本成员，然后更新展示态并关弹窗。
    final authorId = await AuthorService.instance.existingAuthorId();
    if (authorId != null && nickname.isNotEmpty) {
      await SyncService.instance.enqueueProfileChange(
        authorId: authorId,
        nickname: nickname,
      );
    }
    if (!mounted) return;
    // 弹窗可能在等待期间被用户关闭（barrier 不可关但保险起见），
    // dialogContext.mounted 为 false 说明已不在导航栈，直接放弃关窗。
    if (dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
    _nicknameController.text = nickname;
    setState(() {});
    showToast(context, '昵称同步成功');
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
      final url = await AuthorService.instance.changeAvatar(picked.path);
      if (!mounted) return;
      if (url == null) {
        showToast(context, '头像上传失败，请检查云端连接');
        return;
      }
      // changeAvatar 内部已把压缩小图写入展示缓存，此处直接切换展示态即可，
      // 首帧同步命中缓存立即显示新头像（不再等下载原图压缩）。
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
