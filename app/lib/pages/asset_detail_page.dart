import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/asset_account.dart';
import '../models/transfer.dart';
import '../services/theme_service.dart';
import '../services/asset_account_service.dart';
import '../services/transfer_service.dart';
import '../utils/formatters.dart';
import '../widgets/account_avatar.dart';
import 'asset_account_form_page.dart';
import 'asset_trend_page.dart';
import 'search_page.dart';
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
      account.balanceCents = fresh.balanceCents;
    }
    final transfers = await loadTransfersForAccount(account.id);
    if (!mounted) return;
    final entries = <_FlowEntry>[];
    for (final t in transfers) {
      String label(AssetAccount? a, String? fallback) {
        if (a == null) return fallback ?? '';
        return a.displayName;
      }

      final isIn = t.toAccountId == account.id;
      entries.add(_FlowEntry(
        date: t.date,
        createdAt: t.createdAt,
        isIn: isIn,
        amountCents: t.amountCents,
        feeCents: t.feeCents,
        remark: t.remark,
        fromLabel: label(byId[t.fromAccountId], t.fromAccountName),
        toLabel: label(byId[t.toAccountId], t.toAccountName),
        transfer: t,
      ));
    }
    entries.sort((a, b) {
      final d = b.date.compareTo(a.date);
      return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
    });
    setState(() => _flows
      ..clear()
      ..addAll(entries));
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      backgroundColor: colorBackgroundPage,
      appBar: AppBar(
        title: const Text('资产详情'),
        backgroundColor: themeColor,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
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
            child: const Text(
              '趋势图',
              style: textAppBarAction,
            ),
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
            child: const Text(
              '账单',
              style: textAppBarAction,
            ),
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
                          builder: (_) => TransferPage(fromAccount: account),
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
                    () {
                      Navigator.push(
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
              AccountAvatar(account: account, size: iconSizeLarge, color: themeColor),
            ],
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
                onPressed: () => _showAdjustBalanceDialog(context),
                style: FilledButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: colorTextOnPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radiusMedium),
                  ),
                ),
                child: const Text('调整余额'),
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
                const Icon(
                  Icons.swap_horiz,
                  size: iconSizeDefault,
                  color: colorIconGray,
                ),
                const SizedBox(width: spacingXS),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '转账',
                        style: textListItem.copyWith(fontWeight: FontWeight.w600),
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
                      ? Theme.of(
                          context,
                        ).extension<AppThemeColors>()!.primary
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
                color: Theme.of(
                  context,
                ).extension<AppThemeColors>()!.primary,
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
              final text = controller.text.trim();
              final cents = text.isEmpty || double.tryParse(text) == null
                  ? 0
                  : yuanToCents(text);
              account.balanceCents = cents;
              await updateAssetAccount(account);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) setState(() {});
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

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确定删除「${account.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await deleteAssetAccount(account.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionDivider() {
    return Container(width: 1, color: colorDivider);
  }
}

class _FlowEntry {
  final DateTime date;
  final DateTime createdAt;
  final bool isIn;
  final int amountCents;
  final int feeCents;
  final String remark;
  final String fromLabel;
  final String toLabel;
  final Transfer transfer;

  _FlowEntry({
    required this.date,
    required this.createdAt,
    required this.isIn,
    required this.amountCents,
    required this.feeCents,
    required this.remark,
    required this.fromLabel,
    required this.toLabel,
    required this.transfer,
  });
}
