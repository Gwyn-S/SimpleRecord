import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/piggy.dart';
import '../../services/cloud/supabase_service.dart';
import '../../services/core/author_service.dart';
import '../../services/core/theme_service.dart';
import '../../services/data/piggy_service.dart';
import '../../utils/formatters.dart';
import '../../utils/toast.dart';
import '../../widgets/common/busy_dialog.dart';
import '../../widgets/common/common_app_bar.dart';
import 'piggy_detail_page.dart';

/// 小金库总览：我参与的金库列表。
class PiggyPage extends StatefulWidget {
  const PiggyPage({super.key});

  @override
  State<PiggyPage> createState() => _PiggyPageState();
}

class _PiggyPageState extends State<PiggyPage> {
  List<Piggy> _piggies = [];
  Map<String, int> _balances = {};
  Map<String, String> _peerLabels = {};

  @override
  void initState() {
    super.initState();
    _load();
    PiggyService.instance.piggyVersion.addListener(_load);
  }

  @override
  void dispose() {
    PiggyService.instance.piggyVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final piggies = await PiggyService.instance.loadMyPiggies();
    final balances = <String, int>{};
    final peers = <String, String>{};
    for (final p in piggies) {
      balances[p.id] = await PiggyService.instance.balanceOf(p.id);
      peers[p.id] = await _peerLabel(p);
    }
    if (!mounted) return;
    setState(() {
      _piggies = piggies;
      _balances = balances;
      _peerLabels = peers;
    });
  }

  /// 对方展示名：昵称优先，未知时退回邮箱；仅自己（无 peer）显示等待提示。
  Future<String> _peerLabel(Piggy piggy) async {
    final peerId = piggy.peerAuthorIdFor(
      SupabaseManager.instance.email ?? '',
    );
    if (peerId == null || peerId.isEmpty) return '等待对方加入';
    final nick = await AuthorService.instance.displayNameFor(peerId);
    return nick ?? peerId;
  }

  // ==================== 新建 / 加入 ====================

  /// 弹窗样式对齐新增账本弹窗：可输入名称新建，或输入邀请码加入。
  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final navigator = Navigator.of(context, rootNavigator: true);
    await showDialog<void>(
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '小金库名称',
                border: InputBorder.none,
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).extension<AppThemeColors>()!.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: spacingS),
            TextField(
              controller: codeController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                LengthLimitingTextInputFormatter(6),
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              ],
              decoration: InputDecoration(
                labelText: '邀请码',
                border: InputBorder.none,
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).extension<AppThemeColors>()!.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              final code = codeController.text.trim().toUpperCase();
              final name = nameController.text.trim();
              if (code.isNotEmpty) {
                final result = await PiggyService.instance.joinPiggy(code);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                _load();
                switch (result) {
                  case JoinPiggyResult.success:
                    showToast(context, '已加入小金库');
                  case JoinPiggyResult.inviteInvalid:
                    showToast(context, '邀请码无效');
                  case JoinPiggyResult.notReady:
                    showToast(context, '请先登录，或检查网络');
                  case JoinPiggyResult.joinFailed:
                    showToast(context, '网络失败，请重试');
                }
              } else if (name.isNotEmpty) {
                Navigator.pop(dialogContext);
                showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => busyDialog('创建中'),
                );
                final (result, newCode) = await PiggyService.instance.createPiggy(
                  name,
                );
                if (!mounted) return;
                navigator.pop();
                if (result != PiggyCreateResult.success) {
                  switch (result) {
                    case PiggyCreateResult.notSignedIn:
                      showToast(context, '请先登录');
                    case PiggyCreateResult.serverFailed:
                      showToast(context, '网络失败，请重试');
                    case PiggyCreateResult.success:
                      break;
                  }
                  return;
                }
                _load();
                await _showInviteDialog(context, newCode!);
              } else {
                showToast(context, '请输入小金库名称或邀请码');
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _showInviteDialog(BuildContext pageContext, String code) async {
    await showDialog<void>(
      context: pageContext,
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('创建成功', style: textDialogTitle),
            const SizedBox(height: spacingM),
            Text('让对方输入邀请码加入：', style: textSecondary),
            const SizedBox(height: spacingS),
            Text(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                color: colorTextPrimary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!mounted) return;
              showToast(context, '已复制邀请码 $code');
            },
            child: const Text('复制邀请码'),
          ),
        ],
      ),
    );
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
        title: '小金库',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateDialog,
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
      body: ListView(
        padding: const EdgeInsets.all(spacingM),
        children: [
          ..._piggies.map(_buildPiggyTile),
        ],
      ),
    );
  }

  Widget _buildPiggyTile(Piggy piggy) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final balance = _balances[piggy.id] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: spacingM),
      decoration: BoxDecoration(
        color: colorBackgroundCard,
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PiggyDetailPage(piggyId: piggy.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            spacingL,
            spacingSM,
            spacingL,
            spacingSM,
          ),
          child: Row(
            children: [
              Container(
                width: 80,
                height: 100,
                decoration: BoxDecoration(
                  color: themeColor,
                  borderRadius: BorderRadius.circular(radiusMedium),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: spacingXXS),
                child: Text(
                  piggy.name,
                  style: textCardTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _peerLabels[piggy.id]?.isNotEmpty == true
                          ? '对方：${_peerLabels[piggy.id]}'
                          : '等待对方加入',
                      style: textListItem,
                    ),
                    const SizedBox(height: spacingXXS),
                    Text(
                      '邀请码 ${piggy.inviteCode}',
                      style: textItemSub,
                    ),
                  ],
                ),
              ),
              Text(formatAmount(balance), style: textAccountAmount),
              const SizedBox(width: spacingXS),
              Icon(
                Icons.chevron_right,
                size: iconSizeDefault,
                color: colorTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}