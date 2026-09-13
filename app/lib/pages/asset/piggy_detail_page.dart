import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/asset_account.dart';
import '../../models/data/piggy.dart';
import '../../services/cloud/supabase_service.dart';
import '../../services/core/author_service.dart';
import '../../services/core/theme_service.dart';
import '../../services/data/asset_account_service.dart';
import '../../services/data/piggy_service.dart';
import '../../utils/formatters.dart';
import '../../utils/toast.dart';
import '../../widgets/common/common_app_bar.dart';
import '../../widgets/record/account_picker_sheet.dart';

/// 小金库详情：大余额 + 对方信息 + 存入/取出 + 存取流水列表。
class PiggyDetailPage extends StatefulWidget {
  final String piggyId;

  const PiggyDetailPage({super.key, required this.piggyId});

  @override
  State<PiggyDetailPage> createState() => _PiggyDetailPageState();
}

class _PiggyDetailPageState extends State<PiggyDetailPage> {
  Piggy? _piggy;
  int _balance = 0;
  List<PiggyEvent> _events = [];
  String _peerLabel = '';
  String _inviteCode = '';
  Map<String, String> _operatorNames = {};

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
    final piggy = await PiggyService.instance.findPiggy(widget.piggyId);
    if (piggy == null) {
      if (mounted) setState(() => _piggy = null);
      return;
    }
    final balance = await PiggyService.instance.balanceOf(widget.piggyId);
    final events = await PiggyService.instance.loadEvents(widget.piggyId);
    final peerLabel = await _resolvePeerLabel(piggy);
    // 操作者昵称化：本地映射有则用昵称，否则退回邮箱。
    final operatorNames = <String, String>{};
    for (final e in events) {
      if (e.operatorEmail.isEmpty) continue;
      final nick = await AuthorService.instance.displayNameFor(e.operatorEmail);
      operatorNames[e.operatorEmail] = nick ?? e.operatorEmail;
    }
    if (!mounted) return;
    setState(() {
      _piggy = piggy;
      _balance = balance;
      _events = events;
      _peerLabel = peerLabel;
      _inviteCode = piggy.inviteCode;
      _operatorNames = operatorNames;
    });
  }

  Future<String> _resolvePeerLabel(Piggy piggy) async {
    final peerId = piggy.peerAuthorIdFor(
      SupabaseManager.instance.email ?? '',
    );
    if (peerId == null || peerId.isEmpty) return '等待对方加入';
    final nick = await AuthorService.instance.displayNameFor(peerId);
    return nick ?? peerId;
  }

  /// 对方是否已加入。
  bool get _hasPeer => _piggy?.peerAuthorId != null && _piggy!.peerAuthorId!.isNotEmpty;

  Future<void> _copyInviteCode() async {
    final code = _inviteCode;
    if (code.isEmpty) {
      showToast(context, '暂无邀请码');
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showToast(context, '已复制邀请码 $code');
  }

  /// 打开存取弹窗，成功后刷新并提示。
  Future<void> _showOpSheet(bool isDeposit) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorBackgroundCard,
      builder: (_) => _PiggyOpSheet(
        piggyId: widget.piggyId,
        isDeposit: isDeposit,
        currentBalance: _balance,
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      showToast(context, isDeposit ? '存入成功' : '取出成功');
    } else if (ok == false) {
      showToast(context, '网络失败，请重试');
    }
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final piggy = _piggy;
    return Scaffold(
      appBar: CommonAppBar(title: piggy?.name ?? '小金库'),
      body: piggy == null
          ? const Center(child: Text('小金库不存在或已失效', style: textHint))
          : Column(
              children: [
                _buildHeader(themeColor, piggy),
                Expanded(
                  child: _events.isEmpty
                      ? const Center(
                          child: Text('还没有存取记录', style: textHint),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: _events.length,
                          separatorBuilder: (_, _) => Container(
                            height: 1,
                            color: colorDivider,
                          ),
                          itemBuilder: (context, index) =>
                              _buildEventRow(_events[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(Color themeColor, Piggy piggy) {
    return Container(
      color: themeColor,
      padding: const EdgeInsets.fromLTRB(
        spacingL,
        spacingL,
        spacingL,
        spacingXL,
      ),
      child: Column(
        children: [
          Text(_peerLabel, style: textCardMeta),
          const SizedBox(height: spacingXS),
          // 对方加入后隐藏邀请码，防止误传播。
          if (_inviteCode.isNotEmpty && !_hasPeer)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _copyInviteCode,
              child: Padding(
                padding: const EdgeInsets.all(spacingXS),
                child: Text(
                  '邀请码 $_inviteCode（点击复制）',
                  style: textCardMeta,
                ),
              ),
            ),
          const SizedBox(height: spacingS),
          Text(
            formatAmount(_balance),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w600,
              color: colorTextOnPrimary,
            ),
          ),
          const SizedBox(height: spacingS),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _opButton(Icons.arrow_circle_down, '存入', () => _showOpSheet(true)),
              const SizedBox(width: spacingL),
              _opButton(Icons.arrow_circle_up, '取出', () => _showOpSheet(false)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _opButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: colorTextOnPrimary.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusLarge),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: spacingXL,
            vertical: spacingSM,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSizeDefault, color: colorTextOnPrimary),
              const SizedBox(width: spacingXS),
              Text(label, style: textPagerButton),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventRow(PiggyEvent event) {
    final isDeposit = event.isDeposit;
    final color = isDeposit ? colorIncome : colorExpense;
    final sign = isDeposit ? '+' : '-';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        spacingL,
        spacingSM,
        spacingL,
        spacingSM,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: colorIconLightBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDeposit ? Icons.south_west : Icons.north_east,
              size: iconSizeDefault,
              color: colorIconGray,
            ),
          ),
          const SizedBox(width: spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        event.remark.isEmpty ? '小金库存取' : event.remark,
                        style: textListItem,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (event.operatorEmail.isNotEmpty)
                      Flexible(
                        child: Text(
                          ' ${_operatorNames[event.operatorEmail] ?? event.operatorEmail}',
                          style: textItemSub,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: spacingXXS),
                Text(
                  formatDateTime(
                    DateTime.fromMillisecondsSinceEpoch(event.createdAt),
                  ),
                  style: textItemSub,
                ),
              ],
            ),
          ),
          Text(
            '$sign${formatAmount(event.delta.abs())}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 存取弹窗：金额 + 备注 + 记账开关 + 关联账户选项。
class _PiggyOpSheet extends StatefulWidget {
  final String piggyId;
  final bool isDeposit;
  final int currentBalance;

  const _PiggyOpSheet({
    required this.piggyId,
    required this.isDeposit,
    required this.currentBalance,
  });

  @override
  State<_PiggyOpSheet> createState() => _PiggyOpSheetState();
}

class _PiggyOpSheetState extends State<_PiggyOpSheet> {
  final _amountController = TextEditingController();
  final _remarkController = TextEditingController();
  bool _recordEnabled = false;
  AssetAccount? _linkedAccount;
  List<AssetAccount> _accounts = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final accounts = await loadAssetAccounts();
    if (!mounted) return;
    setState(() => _accounts = accounts);
  }

  Future<void> _pickAccount() async {
    final result = await showAccountPicker(
      context,
      accounts: _accounts,
      selectedId: _linkedAccount?.id,
    );
    if (!mounted) return;
    if (result == null) return; // 取消
    if (identical(result, noAccountSelection)) {
      setState(() => _linkedAccount = null);
      return;
    }
    if (result is AssetAccount) {
      setState(() => _linkedAccount = result);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final (cents, error) = parseAmountCents(_amountController.text.trim());
    if (error != null) {
      showToast(context, error);
      return;
    }
    setState(() => _submitting = true);
    final ok = widget.isDeposit
        ? await PiggyService.instance.deposit(
            piggyId: widget.piggyId,
            amountCents: cents,
            remark: _remarkController.text.trim(),
            linkedAccountId: _linkedAccount?.id,
            recordToLedger: _recordEnabled,
          )
        : await PiggyService.instance.withdraw(
            piggyId: widget.piggyId,
            amountCents: cents,
            remark: _remarkController.text.trim(),
            linkedAccountId: _linkedAccount?.id,
            recordToLedger: _recordEnabled,
          );
    if (!mounted) return;
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                spacingL,
                spacingM,
                spacingL,
                spacingS,
              ),
              child: Row(
                children: [
                  Text(
                    widget.isDeposit ? '存入小金库' : '取出小金库',
                    style: textTitleBold,
                  ),
                  const Spacer(),
                  Text('当前余额：${formatAmount(widget.currentBalance)}', style: textItemSub),
                ],
              ),
            ),
            const Divider(height: 1, color: colorDivider),
            Padding(
              padding: const EdgeInsets.all(spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: textAmountInput,
                    decoration: InputDecoration(
                      prefixText: '¥ ',
                      hintText: '0.00',
                      hintStyle: textAmountInput.copyWith(
                        color: colorTextPlaceholder,
                      ),
                      border: InputBorder.none,
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: colorDivider),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: themeColor),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: spacingM),
                  TextField(
                    controller: _remarkController,
                    decoration: const InputDecoration(
                      hintText: '备注（可选）',
                      border: InputBorder.none,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colorDivider),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.transparent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: colorDivider),
            Padding(
              padding: const EdgeInsets.fromLTRB(spacingL, 4, spacingL, 4),
              child: Row(
                children: [
                  const Text('记账', style: textListItem),
                  const Spacer(),
                  ChoiceChip(
                    label: const Text('不记账'),
                    selected: !_recordEnabled,
                    onSelected: (_) => setState(() => _recordEnabled = false),
                  ),
                  const SizedBox(width: spacingS),
                  ChoiceChip(
                    label: const Text('记为收支'),
                    selected: _recordEnabled,
                    onSelected: (_) => setState(() => _recordEnabled = true),
                  ),
                ],
              ),
            ),
            if (_recordEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(spacingL, 4, spacingL, 4),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _pickAccount,
                  child: Row(
                    children: [
                      const Text('关联账户', style: textListItem),
                      const Spacer(),
                      Text(
                        _linkedAccount?.displayName ?? '不关联',
                        style: _linkedAccount == null
                            ? textSecondary
                            : textListItem,
                      ),
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
            const SizedBox(height: spacingM),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: spacingL),
              child: SizedBox(
                height: heightOptionBar,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.isDeposit ? '确认存入' : '确认取出',
                          style: textButtonPrimary,
                        ),
                ),
              ),
            ),
            const SizedBox(height: spacingL),
          ],
        ),
      ),
    );
  }
}