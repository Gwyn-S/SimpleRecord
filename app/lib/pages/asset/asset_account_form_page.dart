import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/asset_account.dart';
import '../../services/cloud/supabase_service.dart';
import '../../services/cloud/vault_op_service.dart';
import '../../services/data/asset_account_service.dart';
import '../../services/data/balance_history_service.dart';
import '../../services/core/theme_service.dart';
import '../../utils/formatters.dart';
import '../../utils/id.dart';
import '../../widgets/common/busy_dialog.dart';

/// 通用账户表单页，覆盖现金/负债/债券/自定义资产（直接表单）与
/// 储蓄卡/信用卡/网络支付/投资（二级页跳转后的三级表单）。
class AddAssetAccountFormPage extends StatefulWidget {
  final String title;
  final String categoryName;
  final String nameLabel;
  final String? presetName;
  final String presetIconPath;
  final AssetAccount? existingAccount;
  final bool nameEditable;
  final bool showCardField;
  final String emptyNameFallback;

  /// 新建类表单云端预创建钩子（可选）：本地落库前调用，返回云端邀请码；
  /// 返回 null 表示云端失败，此时不落本地也不关页。典型场景：小金库新建时
  /// 先建云端金库房间、成功后本地才插入资产账户。
  final Future<String?> Function(BuildContext context, AssetAccount account)?
      onCloudCreate;

  const AddAssetAccountFormPage({
    super.key,
    required this.title,
    required this.categoryName,
    required this.nameLabel,
    required this.nameEditable,
    this.presetName,
    this.presetIconPath = '',
    this.existingAccount,
    this.showCardField = false,
    this.emptyNameFallback = '',
    this.onCloudCreate,
  });

  @override
  State<AddAssetAccountFormPage> createState() =>
      _AddAssetAccountFormPageState();
}

class _AddAssetAccountFormPageState extends State<AddAssetAccountFormPage> {
  final _nameController = TextEditingController();
  final _cardController = TextEditingController();
  final _remarkController = TextEditingController();
  final _balanceController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    final e = widget.existingAccount;
    if (e == null) return;
    if (widget.nameEditable) _nameController.text = e.name;
    _cardController.text = e.cardLast4;
    _remarkController.text = e.remark;
    _balanceController.text = formatAmount(e.balanceCents);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cardController.dispose();
    _remarkController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = widget.nameEditable
        ? (_nameController.text.trim().isEmpty
              ? widget.emptyNameFallback
              : _nameController.text.trim())
        : widget.presetName!;
    final balanceText = _balanceController.text.trim();
    final balanceCents =
        balanceText.isEmpty || double.tryParse(balanceText) == null
        ? 0
        : yuanToCents(balanceText);
final isVault = widget.categoryName == '小金库';
    final account = AssetAccount(
      id: widget.existingAccount?.id ?? genId(),
      categoryName: widget.categoryName,
      name: name,
      balanceCents: balanceCents,
      // 期初只在新建时定为"当前余额"，编辑保持既有期初不变。
      // 金库期初恒为 0：初始余额作为首条「调整」事件走云端重建，避免双算。
      openingBalanceCents: isVault
          ? 0
          : widget.existingAccount?.openingBalanceCents ?? balanceCents,
      remark: _remarkController.text.trim(),
      cardLast4: _cardController.text.trim(),
      iconPath: widget.presetIconPath,
      // 编辑时保留既有邀请码，避免把金库 invite_code 覆盖成空。
      inviteCode: widget.existingAccount?.inviteCode ?? '',
    );
    final onCloud = widget.onCloudCreate;
    if (onCloud != null) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => busyDialog('创建中'),
      );
      String? invite;
      try {
        invite = await onCloud(context, account);
      } finally {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
      if (invite == null) {
        return;
      }
      account.inviteCode = invite;
    }
    if (widget.existingAccount != null) {
      final before = widget.existingAccount!.balanceCents;
      final balanceChanged =
          account.balanceCents != before && account.categoryName == '小金库';
      // 金库改余额时本地调整记录与推送事件共用 entityId/sourceId，幂等防双写。
      final entityId = balanceChanged
          ? '${account.id}-adj-${DateTime.now().microsecondsSinceEpoch}'
          : null;
      await updateAssetAccount(
        account,
        adjustSourceId: entityId ?? '',
        adjustOperatorEmail: SupabaseManager.instance.email ?? '',
      );
      // 编辑小金库：名字/备注变化通告对端（图标不可编辑，不在此列）。
      if (account.categoryName == '小金库') {
        final e = widget.existingAccount!;
        if (e.name != account.name || e.remark != account.remark) {
          await VaultOpService.instance.pushVaultProfile(
            accountId: account.id,
            name: e.name != account.name ? account.name : null,
            remark: e.remark != account.remark ? account.remark : null,
          );
        }
        // 改余额通告云端（新建走 onCloudCreate 后的初始通告）。
        if (balanceChanged) {
          await VaultOpService.instance.pushAdjust(
            accountId: account.id,
            deltaCents: account.balanceCents - before,
            beforeCents: before,
            afterCents: account.balanceCents,
            entityId: entityId,
          );
        }
      }
    } else {
      await insertAssetAccount(account);
      // 新建小金库：期初 0，初始余额本身作为第一条「调整」事件通告云端，
      // B 端加入时据 events 重建金库余额；随后订阅实时通道，否则创建方
      // 收不到对方后续的转账/调整。本地与事件共用 entityId，幂等防双算。
      if (account.categoryName == '小金库') {
        final initId =
            '${account.id}-init-${DateTime.now().microsecondsSinceEpoch}';
        await BalanceHistoryService.instance.recordAdjustment(
          accountId: account.id,
          date: toEpochDay(DateTime.now()),
          deltaCents: account.balanceCents,
          beforeCents: 0,
          afterCents: account.balanceCents,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          sourceId: initId,
          operatorEmail: SupabaseManager.instance.email ?? '',
        );
        await VaultOpService.instance.pushInitialBalance(
          account,
          entityId: initId,
        );
        await VaultOpService.instance.activateVault(account.id);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
            child: _buildField(
              widget.nameLabel,
              widget.nameEditable
                  ? TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    )
                  : Text(widget.presetName!, style: textBody),
            ),
          ),
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorDivider,
          ),
          if (widget.showCardField) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: spacingL,
                vertical: spacingM,
              ),
              child: _buildField(
                '卡号(后四位)',
                TextField(
                  controller: _cardController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: '非必填',
                    hintStyle: textHint,
                  ),
                ),
              ),
            ),
            const Divider(
              height: 1,
              thickness: borderWidthThin,
              color: colorDivider,
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: spacingL,
              vertical: spacingM,
            ),
            child: _buildField(
              '备注',
              TextField(
                controller: _remarkController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: '非必填',
                  hintStyle: textHint,
                ),
              ),
            ),
          ),
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorDivider,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: spacingL,
              vertical: spacingM,
            ),
            child: _buildField(
              '余额',
              TextField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
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
                  _save();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: colorTextOnPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radiusXS),
                  ),
                ),
                child: const Text('保存'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            Text(label, style: textBody),
            const Spacer(),
            SizedBox(width: constraints.maxWidth * 0.5, child: child),
          ],
        );
      },
    );
  }
}
