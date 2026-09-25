import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/asset_account.dart';
import '../../models/data/transfer.dart';
import '../../services/cloud/vault_op_service.dart';
import '../../services/core/theme_service.dart';
import '../../services/data/asset_account_service.dart';
import '../../services/data/transfer_service.dart';
import '../../utils/calculator.dart';
import '../../utils/id.dart';
import '../../widgets/common/common_app_bar.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/option_bar_item.dart';
import '../../widgets/common/account_avatar.dart';
import '../../utils/toast.dart';
import '../../widgets/record/account_picker_sheet.dart';
import '../../widgets/record/calc_keyboard.dart';
import '../../widgets/common/date_picker_sheet.dart';

class TransferPage extends StatefulWidget {
  final AssetAccount? fromAccount;
  final AssetAccount? toAccount;
  final Transfer? initialTransfer;

  const TransferPage({
    super.key,
    this.fromAccount,
    this.toAccount,
    this.initialTransfer,
  });

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  AssetAccount? _from;
  AssetAccount? _to;
  String _amount = '0';
  String _fee = '0';
  DateTime _selectedDate = DateTime.now();
  final _remarkController = TextEditingController();
  bool _isEdit = false;
  List<AssetAccount> _accounts = [];

  @override
  void initState() {
    super.initState();
    final t = widget.initialTransfer;
    if (t != null) {
      _loadEdit(t);
    } else {
      _from = widget.fromAccount;
      _to = widget.toAccount;
    }
    _loadEndpoints();
  }

  Future<void> _loadEndpoints() async {
    final accounts = await loadAssetAccounts();
    if (!mounted) return;
    setState(() => _accounts = accounts);
  }

  Future<void> _loadEdit(Transfer t) async {
    final accounts = await loadAssetAccounts();
    final byId = {for (final a in accounts) a.id: a};
    if (!mounted) return;
    setState(() {
      _isEdit = true;
      _from = byId[t.fromAccountId];
      _to = byId[t.toAccountId];
      _amount = formatAmountEdit(t.amountCents);
      _fee = formatAmountEdit(t.feeCents);
      _selectedDate = t.date;
      _remarkController.text = t.remark;
    });
    await _loadEndpoints();
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  String get _feeLabel => '手续费';

  Future<bool> _saveTransfer() async {
    final (amountCents, amountError) = parseAmountCents(_amount);
    if (amountError != null) {
      safeShowToast(context, amountError);
      return false;
    }
    final from = _from;
    final to = _to;
    if (from == null) {
      safeShowToast(context, '请选择转出账户');
      return false;
    }
    if (to == null) {
      safeShowToast(context, '请选择转入账户');
      return false;
    }
    final feeResult = evaluate(_fee);
    final feeParsed = double.tryParse(feeResult);
    final feeCents = (feeParsed == null || feeParsed <= 0)
        ? 0
        : yuanToCents(feeResult);
    final t = widget.initialTransfer;
    if (t != null) {
      await updateTransfer(
        Transfer(
          id: t.id,
          fromAccountId: from.id,
          toAccountId: to.id,
          amountCents: amountCents,
          feeCents: feeCents,
          remark: _remarkController.text,
          date: _selectedDate,
          createdAt: t.createdAt,
          operatorEmail: t.operatorEmail,
          operatorNickname: t.operatorNickname,
          operatorAvatarUrl: t.operatorAvatarUrl,
        ),
      );
      await VaultOpService.instance.pushTransfer(
        Transfer(
          id: t.id,
          fromAccountId: from.id,
          toAccountId: to.id,
          amountCents: amountCents,
          feeCents: feeCents,
          remark: _remarkController.text,
          date: _selectedDate,
          createdAt: t.createdAt,
          operatorEmail: t.operatorEmail,
          operatorNickname: t.operatorNickname,
          operatorAvatarUrl: t.operatorAvatarUrl,
        ),
      );
    } else {
      final newId = genId();
      final now = DateTime.now();
      await insertTransfer(
        fromAccountId: from.id,
        toAccountId: to.id,
        amountCents: amountCents,
        feeCents: feeCents,
        remark: _remarkController.text,
        date: _selectedDate,
        id: newId,
      );
      await VaultOpService.instance.pushTransfer(
        Transfer(
          id: newId,
          fromAccountId: from.id,
          toAccountId: to.id,
          amountCents: amountCents,
          feeCents: feeCents,
          remark: _remarkController.text,
          date: _selectedDate,
          createdAt: now,
        ),
      );
    }
    return true;
  }

  Future<void> _pickFrom() async {
    if (_accounts.isEmpty) await _loadEndpoints();
    if (!mounted) return;
    final result = await showAccountPicker(
      context,
      accounts: _accounts,
      selectedId: _from?.id,
    );
    if (result == null || !mounted) return;
    if (result == noAccountSelection) return;
    setState(() => _from = result as AssetAccount);
  }

  Future<void> _pickTo() async {
    if (_accounts.isEmpty) await _loadEndpoints();
    if (!mounted) return;
    final result = await showAccountPicker(
      context,
      accounts: _accounts,
      selectedId: _to?.id,
    );
    if (result == null || !mounted) return;
    if (result == noAccountSelection) return;
    setState(() => _to = result as AssetAccount);
  }

  Future<void> _editFee() async {
    final controller = TextEditingController(text: _fee);
    final result = await showDialog<String>(
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
            hintText: '请输入手续费',
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
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(dialogContext, controller.text);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final text = result.trim();
    if (text.isEmpty || double.tryParse(text) == null) {
      setState(() => _fee = '0');
    } else {
      setState(() => _fee = text);
    }
  }

  void _onDelete() {
    if (!_isEdit) {
      safeShowToast(context, '当前是新建转账记录');
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text('确定删除这笔转账记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final t = widget.initialTransfer!;
              await deleteTransfer(t.id);
              await VaultOpService.instance.pushTransfer(
                Transfer(
                  id: t.id,
                  fromAccountId: t.fromAccountId,
                  toAccountId: t.toAccountId,
                  amountCents: t.amountCents,
                  feeCents: t.feeCents,
                  remark: t.remark,
                  date: t.date,
                  createdAt: t.createdAt,
                  operatorEmail: t.operatorEmail,
                  operatorNickname: t.operatorNickname,
                  operatorAvatarUrl: t.operatorAvatarUrl,
                ),
                op: 'delete',
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) Navigator.pop(context, true);
            },
            child: const Text('删除', style: TextStyle(color: colorDelete)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      backgroundColor: colorBackgroundPage,
      appBar: CommonAppBar(
        title: '转账',
        actions: [
          if (_isEdit)
            TextButton(
              onPressed: _onDelete,
              child: const Text(
                '删除',
                style: TextStyle(color: colorTextOnPrimary, fontSize: 16),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildAccountSection(),
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorBorderKeyboard,
          ),
          Container(
            height: heightOptionBar,
            color: colorBackgroundCard,
            padding: const EdgeInsets.symmetric(horizontal: spacingL),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _remarkController,
                    maxLength: 20,
                    style: textBody,
                    cursorColor: themeColor,
                    decoration: InputDecoration(
                      hintText: '备注',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: colorTextHintLight,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    amountPreview(_amount),
                    textAlign: TextAlign.right,
                    style: textAmountInput.copyWith(color: themeColor),
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorBorderKeyboard,
          ),
          _buildOptionBar(),
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorBorderKeyboard,
          ),
          CalcKeyboard(
            amount: _amount,
            onChanged: (v) => setState(() => _amount = v),
            extraLabel: '返回',
            onExtra: () => Navigator.pop(context),
            onDone: () {
              FocusManager.instance.primaryFocus?.unfocus();
              _saveTransfer().then((ok) {
                if (ok && context.mounted) Navigator.pop(context, true);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSection() {
    return Column(
      children: [
        _buildSectionLabel('转出账户'),
        _buildAccountValue(_from, onTap: _pickFrom),
        _buildSectionLabel('转入账户'),
        _buildAccountValue(_to, onTap: _pickTo),
        Container(height: spacingXL, color: colorBackgroundLight),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Container(
      width: double.infinity,
      color: colorBackgroundLight,
      padding: const EdgeInsets.symmetric(
        horizontal: spacingL,
        vertical: spacingS,
      ),
      child: Text(label, style: textItemSub),
    );
  }

  Widget _buildAccountValue(AssetAccount? account, {required VoidCallback onTap}) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Container(
      color: colorBackgroundCard,
      padding: const EdgeInsets.symmetric(
        horizontal: spacingL,
        vertical: spacingS,
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            if (account == null)
              const SizedBox(width: iconSizeLarge, height: iconSizeLarge)
            else
              AccountAvatar(
                account: account,
                size: iconSizeLarge,
                color: themeColor,
              ),
            const SizedBox(width: spacingM),
            Expanded(
              child: Text(
                account?.displayName ?? '请选择',
                style: textListItem,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: iconSizeMedium,
              color: colorGrey300,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionBar() {
    return Container(
      height: heightOptionBar,
      color: colorBackgroundCard,
      padding: const EdgeInsets.symmetric(horizontal: spacingL),
      child: Row(
        children: [
          OptionBarItem(
            icon: Icons.calendar_today_outlined,
            label: formatSelectedDate(_selectedDate),
            onTap: () async {
              final picked = await showDatePickerSheet(context, _selectedDate);
              if (picked == null || !mounted) return;
              setState(() => _selectedDate = picked);
            },
          ),
          const SizedBox(width: spacingXXL),
          OptionBarItem(
            icon: Icons.edit_outlined,
            label: _feeLabel,
            onTap: _editFee,
          ),
        ],
      ),
    );
  }
}