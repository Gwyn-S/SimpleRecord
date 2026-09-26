import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../services/cloud/supabase_service.dart';
import '../../services/cloud/vault_op_service.dart';
import '../../services/core/theme_service.dart';
import '../../utils/log.dart';
import '../../utils/toast.dart';
import '../../widgets/common/busy_dialog.dart';

/// 加入小金库：输入邀请码，云端校验接入后完成加入。
/// 成功：本地落库金库账户 + 全量拉取历史重建 + 订阅实时。
class VaultJoinPage extends StatefulWidget {
  const VaultJoinPage({super.key});

  @override
  State<VaultJoinPage> createState() => _VaultJoinPageState();
}

class _VaultJoinPageState extends State<VaultJoinPage> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      showToast(context, '请输入邀请码');
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => busyDialog('加入中'),
    );
    final supabase = SupabaseManager.instance;
    if (!await supabase.ensureSignedIn()) {
      navigator.pop();
      if (mounted) {
        showToast(context, '加入失败：请先登录账号');
      }
      return;
    }
    try {
      final error = await VaultOpService.instance.joinVaultByInvite(code);
      navigator.pop();
      if (!mounted) return;
      if (error == null) {
        showToast(context, '加入成功');
        Navigator.pop(context, true);
      } else {
        showToast(context, error);
      }
    } catch (e) {
      navigator.pop();
      appLog('[vault] join failed: $e');
      if (mounted) showToast(context, '加入失败，请检查网络后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('加入小金库'),
        backgroundColor: themeColor,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: spacingL,
              vertical: spacingM,
            ),
            child: Row(
              children: [
                Text('邀请码', style: textBody),
                const Spacer(),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _codeController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorDivider,
          ),
          Padding(
            padding: const EdgeInsets.all(spacingL),
            child: SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  _join();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: colorTextOnPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radiusXS),
                  ),
                ),
                child: const Text('加入'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}