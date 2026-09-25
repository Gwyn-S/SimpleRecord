import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/asset_account.dart';
import '../../models/data/transfer.dart';
import '../../services/cloud/supabase_service.dart';
import '../../services/cloud/vault_op_service.dart';
import '../../services/core/author_service.dart';
import '../../services/core/theme_service.dart';
import '../../services/data/asset_account_service.dart';
import '../../services/data/balance_history_service.dart';
import '../../services/data/transfer_service.dart';
import '../../utils/formatters.dart';
import '../../utils/toast.dart';
import '../../widgets/common/common_app_bar.dart';
import '../../widgets/common/account_avatar.dart';
import '../../widgets/common/author_avatar.dart';
import 'asset_account_form_page.dart';
import 'asset_trend_page.dart';
import '../record/search_page.dart';
import 'transfer_page.dart';

class AssetDetailPage extends StatefulWidget {
  final AssetAccount account;

  const AssetDetailPage({super.key, required this.account});

  @override
  State<AssetDetailPage> createState() => _AssetDetailPageState();
}

class _AssetDetailPageState extends State<AssetDetailPage> {
  AssetAccount get account => widget.account;

  final List<_FlowEntry> _flows = [];

  @override
  void initState() {
    super.initState();
    assetAccountsVersion.addListener(_loadFlows);
    transfersVersion.addListener(_loadFlows);
    _loadFlows();
  }

  @override
  void dispose() {
    assetAccountsVersion.removeListener(_loadFlows);
    transfersVersion.removeListener(_loadFlows);
    super.dispose();
  }

  Future<void> _loadFlows() async {
    final accounts = await loadAssetAccounts();
    final byId = {for (final a in accounts) a.id: a};
    final fresh = byId[account.id];
    if (fresh != null) {
      // 同步所有可变字段，确保改名/备注/卡号/图标/余额修改后立即反映到卡片。
      account.categoryName = fresh.categoryName;
      account.name = fresh.name;
      account.balanceCents = fresh.balanceCents;
      account.openingBalanceCents = fresh.openingBalanceCents;
      account.remark = fresh.remark;
      account.cardLast4 = fresh.cardLast4;
      account.iconPath = fresh.iconPath;
      account.inviteCode = fresh.inviteCode;
    }
    if (!mounted) {
      return;
    }
    final transfers = await loadTransfersForAccount(account.id);
    final adjustments =
        await BalanceHistoryService.instance.adjustmentsForAccount(account.id);
    if (!mounted) return;
    final entries = <_FlowEntry>[];
    for (final t in transfers) {
      String label(AssetAccount? a, String? fallback) {
        if (a == null) return fallback ?? '';
        return a.displayName;
      }

      final isIn = t.toAccountId == account.id;
      entries.add(
        _FlowEntry(
          date: t.date,
          createdAt: t.createdAt,
          isIn: isIn,
          amountCents: t.amountCents,
          feeCents: t.feeCents,
          remark: t.remark,
          fromLabel: label(byId[t.fromAccountId], t.fromAccountName),
          toLabel: label(byId[t.toAccountId], t.toAccountName),
          transfer: t,
          isShared:
              VaultOpService.instance.isSharedVault(byId[t.fromAccountId]) ||
              VaultOpService.instance.isSharedVault(byId[t.toAccountId]),
        ),
      );
    }
    for (final a in adjustments) {
      entries.add(
        _FlowEntry(
          date: fromEpochDay(a['date'] as int),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            a['created_at'] as int,
          ),
          type: _FlowType.adjustment,
          adjustmentId: a['id'] as int,
          deltaCents: a['delta'] as int,
          beforeCents: a['before_cents'] as int,
          afterCents: a['after_cents'] as int,
        ),
      );
    }
    entries.sort((a, b) {
      final d = b.date.compareTo(a.date);
      return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
    });
    setState(
      () => _flows
        ..clear()
        ..addAll(entries),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      backgroundColor: colorBackgroundPage,
      appBar: CommonAppBar(
        title: '资产详情',
        actions: [
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssetTrendPage(account: account),
              ),
            ),
            style: TextButton.styleFrom(
              shape: const RoundedRectangleBorder(),
              backgroundColor: Colors.transparent,
              overlayColor: Colors.transparent,
              foregroundColor: colorTextOnPrimary,
            ),
            child: const Text('趋势图', style: textAppBarAction),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SearchPage(initialAccountId: account.id),
              ),
            ),
            style: TextButton.styleFrom(
              shape: const RoundedRectangleBorder(),
              backgroundColor: Colors.transparent,
              overlayColor: Colors.transparent,
              foregroundColor: colorTextOnPrimary,
            ),
            child: const Text('账单', style: textAppBarAction),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    spacingL,
                    spacingL,
                    spacingL,
                    spacingM,
                  ),
                  child: _buildAccountCard(themeColor),
                ),
                if (_flows.isNotEmpty)
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        spacingL,
                        0,
                        spacingL,
                        spacingL,
                      ),
                      children: _buildFlowGroups(),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: colorBackgroundCard,
              border: Border(top: BorderSide(color: colorDivider)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _buildAction(
                    context,
                    '转账',
                    Icons.swap_horiz,
                    colorTextPrimary,
                    () async {
                      final changed = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TransferPage(
                            fromAccount:
                                account.categoryName == '小金库'
                                ? null
                                : account,
                            toAccount:
                                account.categoryName == '小金库'
                                ? account
                                : null,
                          ),
                        ),
                      );
                      if (changed == true && mounted) setState(() {});
                    },
                  ),
                  _buildActionDivider(),
                  _buildAction(
                    context,
                    '修改',
                    Icons.edit_outlined,
                    colorTextPrimary,
                    () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddAssetAccountFormPage(
                            title: '修改${account.categoryName}',
                            categoryName: account.categoryName,
                            nameLabel: _isCardAccount ? '所在银行' : '名称',
                            nameEditable: !_isCardAccount,
                            existingAccount: account,
                            presetName: account.name,
                            presetIconPath: account.iconPath,
                            showCardField: _isCardAccount,
                            emptyNameFallback: account.name,
                          ),
                        ),
                      );
                      if (mounted) await _loadFlows();
                    },
                  ),
                  _buildActionDivider(),
                  _buildAction(
                    context,
                    '删除',
                    Icons.delete_outline,
                    colorTextPrimary,
                    () => _showDeleteDialog(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(Color themeColor) {
    return Container(
      padding: const EdgeInsets.all(spacingL),
      decoration: BoxDecoration(
        color: colorBackgroundCard,
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                account.displayName,
                style: textListItem.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: spacingXS),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorTagBackground,
                  borderRadius: BorderRadius.circular(radiusXS),
                ),
                child: Text(
                  account.categoryName,
                  style: const TextStyle(color: colorTagText, fontSize: 12),
                ),
              ),
              const Spacer(),
              AccountAvatar(
                account: account,
                size: iconSizeLarge,
                color: themeColor,
              ),
            ],
          ),
          const SizedBox(height: spacingXS),
          Text(
            account.remark.isEmpty ? ' ' : account.remark,
            style: textItemSub,
          ),
          const SizedBox(height: spacingM),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatAmount(account.balanceCents),
                      style: textBalanceLarge,
                    ),
                    const SizedBox(height: spacingXXS),
                    const Text('余额', style: textItemSub),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () {
                  if (account.categoryName == '小金库') {
                    _copyInviteCode(context);
                  } else {
                    _showAdjustBalanceDialog(context);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: colorTextOnPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radiusMedium),
                  ),
                ),
                child: Text(
                  account.categoryName == '小金库'
                      ? account.inviteCode
                      : '调整余额',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFlowGroups() {
    final groups = <DateTime, List<_FlowEntry>>{};
    for (final f in _flows) {
      final key = DateTime(f.date.year, f.date.month, f.date.day);
      groups.putIfAbsent(key, () => []).add(f);
    }
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final key in sortedKeys)
        Padding(
          padding: const EdgeInsets.only(bottom: spacingM),
          child: Container(
            decoration: BoxDecoration(
              color: colorBackgroundCard,
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    spacingL,
                    spacingM,
                    spacingL,
                    spacingS,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatDate(key),
                      style: const TextStyle(
                        fontSize: 16,
                        color: colorTextPrimary,
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < groups[key]!.length; i++)
                  Padding(
                    padding: const EdgeInsets.all(spacingL),
                    child: _buildTransferRow(groups[key]![i]),
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _buildTransferRow(_FlowEntry f) {
    if (f.type == _FlowType.adjustment) {
      final delta = f.deltaCents;
      final deltaText =
          '${delta > 0 ? '+' : '-'}${formatAmount(delta.abs())}';
      return InkWell(
        onTap: () => _showDeleteAdjustDialog(f),
        child: Row(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/icons/adjust_balance.svg',
                    width: iconSizeDefault,
                    height: iconSizeDefault,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: spacingXS),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '调整余额',
                          style: textListItem.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: spacingXS),
                        Text(
                          '${formatAmount(f.beforeCents)} -> ${formatAmount(f.afterCents)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textItemSub,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: spacingM),
            Text(
              deltaText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: delta > 0
                    ? Theme.of(context).extension<AppThemeColors>()!.primary
                    : colorExpense,
              ),
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransferPage(initialTransfer: f.transfer),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/icons/transfer.svg',
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: spacingXS),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              '转账',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (f.isShared &&
                              f.transfer!.operatorNickname.isNotEmpty) ...[
                            const SizedBox(width: spacingXS),
                            if (AuthorService.instance.recordAuthorDisplay ==
                                AuthorService.recordDisplayAvatar)
                              AuthorAvatar(
                                url: f.transfer!.operatorAvatarUrl,
                                size: 20,
                                cornerRadius: 4,
                              )
                            else
                              Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: colorTagBackground,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  f.transfer!.operatorNickname,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: colorTagText,
                                    fontSize: 12,
                                    height: 1,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: spacingXS),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (f.remark.isNotEmpty) ...[
                            Text(
                              f.remark,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textItemSub,
                            ),
                            const SizedBox(width: spacingXS),
                          ],
                          Text(
                            f.feeCents == 0
                                ? '手续费0'
                                : '手续费${formatAmount(f.feeCents)}',
                            style: textItemSub,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: spacingM),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${f.isIn ? '转入' : '转出'}：¥${formatAmount(f.amountCents)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: f.isIn
                      ? Theme.of(context).extension<AppThemeColors>()!.primary
                      : colorExpense,
                ),
              ),
              const SizedBox(height: spacingXS),
              Text('${f.fromLabel}->${f.toLabel}', style: textItemSub),
            ],
          ),
        ],
      ),
    );
  }

  /// 复制邀请码到剪贴板。
  void _copyInviteCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: account.inviteCode));
    showToast(context, '邀请码已复制');
  }

  void _showAdjustBalanceDialog(BuildContext context) {
    final controller = TextEditingController(
      text: formatAmount(account.balanceCents),
    );
    showDialog(
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
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            hintText: '请输入余额',
            border: InputBorder.none,
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: colorDivider),
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
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              final text = controller.text.trim();
              final cents = text.isEmpty || double.tryParse(text) == null
                  ? 0
                  : yuanToCents(text);
              final before = account.balanceCents;
              account.balanceCents = cents;
              await updateAssetAccount(account);
              await VaultOpService.instance.pushAdjust(
                accountId: account.id,
                deltaCents: cents - before,
                beforeCents: before,
                afterCents: cents,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              await _loadFlows();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildAction(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: spacingM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSizeDefault, color: color),
              const SizedBox(width: spacingXS),
              Text(label, style: textBody.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isCardAccount =>
      account.categoryName == '储蓄卡' || account.categoryName == '信用卡';

  void _showDeleteAdjustDialog(_FlowEntry f) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text('确定删除本次余额调整吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await BalanceHistoryService.instance
                  .deleteAdjustment(account.id, f.adjustmentId);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              await _loadFlows();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    final isShared = account.categoryName == '小金库';
    final base = isShared
        ? '确定删除「${account.name}」吗？\n该资产是多人资产，云端将一并删除。'
        : '确定删除「${account.name}」吗？';
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(base),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              if (isShared) {
                final deleted = await SupabaseManager.instance.deleteVault(
                  account.id,
                );
                if (!deleted) {
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    showToast(dialogContext, '云端删除失败，请重试');
                  }
                  return;
                }
              }
              await deleteAssetAccount(account.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionDivider() {
    return Container(width: 1, color: colorDivider);
  }
}

enum _FlowType { transfer, adjustment }

class _FlowEntry {
  final DateTime date;
  final DateTime createdAt;
  final bool isIn;
  final int amountCents;
  final int feeCents;
  final String remark;
  final String fromLabel;
  final String toLabel;
  final Transfer? transfer;
  final bool isShared;

  final _FlowType type;
  final int adjustmentId;
  final int deltaCents;
  final int beforeCents;
  final int afterCents;

  _FlowEntry({
    required this.date,
    required this.createdAt,
    this.isIn = false,
    this.amountCents = 0,
    this.feeCents = 0,
    this.remark = '',
    this.fromLabel = '',
    this.toLabel = '',
    this.transfer,
    this.isShared = false,
    this.type = _FlowType.transfer,
    this.adjustmentId = 0,
    this.deltaCents = 0,
    this.beforeCents = 0,
    this.afterCents = 0,
  });
}
