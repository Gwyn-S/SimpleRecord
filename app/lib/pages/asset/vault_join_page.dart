import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../services/core/theme_service.dart';
import '../../utils/toast.dart';

/// 加入小金库（页面占位）：输入邀请码，云端校验接入后完成加入。
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

  void _join() {
    if (_codeController.text.trim().isEmpty) {
      showToast(context, '请输入邀请码');
      return;
    }
    showToast(context, '云端加入功能开发中');
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