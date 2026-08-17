import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/asset_account.dart';
import '../models/transfer.dart';
import '../services/theme_service.dart';
import '../services/asset_account_service.dart';
import '../services/transfer_service.dart';
import '../utils/calculator.dart';
import '../utils/formatters.dart';
import '../widgets/option_bar_item.dart';
import '../widgets/account_avatar.dart';
import '../utils/toast.dart';
import '../widgets/account_picker_sheet.dart';
import '../widgets/calc_keyboard.dart';
import '../widgets/date_picker_sheet.dart';

class TransferPage extends StatefulWidget {
  final AssetAccount? fromAccount;
  final Transfer? initialTransfer;

  const TransferPage({super.key, this.fromAccount, this.initialTransfer});

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  AssetAccount? _fromAccount;
  AssetAccount? _toAccount;
  String _amount = '0';
  String _fee = '0';
  DateTime _selectedDate = DateTime.now();
  final _remarkController = TextEditingController();
  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTransfer;
    if (t != null) {
      _loadEdit(t);
    } else {
      _fromAccount = widget.fromAccount;
    }
  }

  Future<void> _loadEdit(Transfer t) async {
    final accounts = await loadAssetAccounts();
    final byId = {for (final a in accounts) a.id: a};
    if (!mounted) return;
    setState(() {
      _isEdit = true;
      _fromAccount = byId[t.fromAccountId] ?? widget.fromAccount;
      _toAccount = byId[t.toAccountId];
      _amount = (t.amountCents / 100).toStringAsFixed(2);
      _fee = (t.feeCents / 100).toStringAsFixed(2);
      _selectedDate = t.date;
      _remarkController.text = t.remark;
    });
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  String get _feeLabel => '手续费';

  void _showMessage(String text) {
    if (!mounted) return;
    showToast(context, text);
  }

  Future<bool> _saveTransfer() async {
    final (amountCents, amountError) = parseAmountCents(_amount);
    if (amountError != null) {
      _showMessage(amountError);
      return false;
    }
    final feeResult = evaluate(_fee);
    final feeParsed = double.tryParse(feeResult);
    final feeCents = (feeParsed == null || feeParsed <= 0)
        ? 0
        : yuanToCents(feeResult);
    final toAccount = _toAccount;
    if (toAccount == null) {
      _showMessage('请选择转入账户');
      return false;
    }
    final fromAccount = _fromAccount;
    if (fromAccount == null) {
      _showMessage('转出账户无效');
      return false;
    }
    final t = widget.initialTransfer;
    if (t != null) {
      await updateTransfer(Transfer(
        id: t.id,
        fromAccountId: fromAccount.id,
        toAccountId: toAccount.id,
        amountCents: amountCents,
        feeCents: feeCents,
        remark: _remarkController.text,
        date: _selectedDate,
        createdAt: t.createdAt,
      ));
    } else {
      await insertTransfer(
        fromAccountId: fromAccount.id,
        toAccountId: toAccount.id,
        amountCents: amountCents,
        feeCents: feeCents,
        remark: _remarkController.text,
        date: _selectedDate,
      );
    }
    return true;
  }

  Future<void> _pickToAccount() async {
    final accounts = await loadAssetAccounts();
    if (!mounted) return;
    final others = accounts.where((a) => a.id != _fromAccount?.id).toList();
    if (others.isEmpty) {
      _showMessage('暂无其他账户');
      return;
    }
    final result = await showAccountPicker(
      context,
      accounts: others,
      selectedId: _toAccount?.id,
    );
    if (result == null || !mounted) return;
    if (result == noAccountSelection) return;
    if (result is AssetAccount) {
      setState(() => _toAccount = result);
    }
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
            onPressed: () => Navigator.pop(dialogContext, controller.text),
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
      _showMessage('当前是新建转账记录');
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除转账'),
        content: const Text('确定删除这笔转账记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await deleteTransfer(widget.initialTransfer!.id);
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
      appBar: AppBar(
        title: const Text('转账'),
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
          const Divider(height: 1, thickness: borderWidthThin, color: colorBorderKeyboard),
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
                      hintStyle: TextStyle(fontSize: 14, color: colorTextHintLight),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    endsWithOp(_amount)
                        ? _amount
                        : _amount.contains(RegExp(r'[+\-×÷]'))
                            ? '$_amount=${evaluate(_amount)}'
                            : _amount,
                    textAlign: TextAlign.right,
                    style: textAmountInput.copyWith(color: themeColor),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: borderWidthThin, color: colorBorderKeyboard),
          _buildOptionBar(),
          const Divider(height: 1, thickness: borderWidthThin, color: colorBorderKeyboard),
          CalcKeyboard(
            amount: _amount,
            onChanged: (v) => setState(() => _amount = v),
            extraLabel: '返回',
            onExtra: () => Navigator.pop(context),
            onDone: () {
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
        _buildAccountValue(_fromAccount),
        _buildSectionLabel('转入账户'),
        _buildAccountValue(_toAccount, onTap: _pickToAccount),
        Container(height: spacingXL, color: colorBackgroundLight),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Container(
      width: double.infinity,
      color: colorBackgroundLight,
      padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingS),
      child: Text(label, style: textItemSub),
    );
  }

  Widget _buildAccountValue(AssetAccount? account, {VoidCallback? onTap}) {
    return Container(
      color: colorBackgroundCard,
      padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingS),
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
                color: Theme.of(context).extension<AppThemeColors>()!.primary,
              ),
            const SizedBox(width: spacingM),
            Expanded(
              child: Text(
                account?.name ?? '请选择',
                style: textListItem,
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: iconSizeMedium, color: colorGrey300),
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

