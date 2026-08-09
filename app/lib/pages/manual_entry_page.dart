import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../models/category.dart';
import '../models/record.dart';
import '../models/asset_account.dart';
import '../services/record_service.dart';
import '../services/asset_account_service.dart';
import '../utils/calculator.dart';
import '../utils/formatters.dart';
import '../utils/id.dart';
import '../utils/toast.dart';
import '../widgets/account_picker_sheet.dart';
import '../widgets/date_picker_sheet.dart';

class ManualEntryPage extends StatefulWidget {
  final Record? initialRecord;
  const ManualEntryPage({super.key, this.initialRecord});

  @override
  State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  bool _isExpense = true;
  int? _selectedCategory = 0;
  String _amount = '0';
  DateTime _selectedDate = DateTime.now();
  AssetAccount? _selectedAccount;
  final _remarkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecord;
    if (r != null) {
      _isExpense = r.isExpense;
      final cats = r.isExpense ? expenseCategories : incomeCategories;
      final idx = cats.indexWhere((c) => c.name == r.categoryName);
      _selectedCategory = idx >= 0 ? idx : null;
      _amount = (r.amountCents / 100).toStringAsFixed(2);
      _selectedDate = r.date;
      _remarkController.text = r.remark;
      if (r.accountId != null) _loadSelectedAccount(r.accountId!);
    }
  }

  Future<void> _loadSelectedAccount(String id) async {
    final accounts = await loadAssetAccounts();
    if (!mounted) return;
    for (final a in accounts) {
      if (a.id == id) {
        setState(() => _selectedAccount = a);
        return;
      }
    }
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  String _getCategoryName() {
    final cats = _isExpense ? expenseCategories : incomeCategories;
    if (_selectedCategory == null || _selectedCategory! >= cats.length) return '其他';
    return cats[_selectedCategory!].name;
  }

  Future<bool> _saveRecord() async {
    final result = evaluate(_amount);
    final parsed = double.tryParse(result);
    if (parsed == null) {
      _showMessage('金额无效');
      return false;
    }
    final amountCents = yuanToCents(result);
    if (amountCents <= 0) {
      _showMessage('请输入金额');
      return false;
    }
    final origin = widget.initialRecord;
    final record = Record(
      id: origin?.id ?? genId(),
      ledgerId: origin?.ledgerId ?? currentLedgerId.value,
      accountId: _selectedAccount?.id,
      isExpense: _isExpense,
      categoryName: _getCategoryName(),
      amountCents: amountCents,
      remark: _remarkController.text,
      date: _selectedDate,
      createdAt: origin?.createdAt ?? DateTime.now(),
    );
    if (origin != null) {
      await updateRecord(record);
    } else {
      await insertRecord(record);
    }
    return true;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    showToast(context, text);
  }

  void _onKeyPressed(String key) {
    if (key == '再记') {
      _saveRecord().then((ok) {
        if (!ok || !mounted) return;
        setState(() {
          _amount = '0';
          _remarkController.clear();
          _selectedCategory = 0;
          _selectedAccount = null;
        });
      });
      return;
    }
    if (key == '完成') {
      _saveRecord().then((ok) {
        if (ok && mounted) Navigator.pop(context);
      });
      return;
    }
    setState(() {
      if (key == 'C') {
        _amount = '0';
      } else if (key == '⌫') {
        if (_amount.length > 1) {
          _amount = _amount.substring(0, _amount.length - 1);
        } else {
          _amount = '0';
        }
      } else if (key == '.') {
        final segment = _amount.split(RegExp(r'[+\-×÷]')).last;
        if (!segment.contains('.')) _amount += '.';
      } else if (key == '00') {
        final segment = _amount.split(RegExp(r'[+\-×÷]')).last;
        if (segment.contains('.')) {
          final decimals = segment.split('.')[1];
          if (decimals.isEmpty) {
            _amount += '00';
          } else if (decimals.length == 1) {
            _amount += '0';
          }
        } else if (segment != '0' && segment != '00') {
          _amount += '00';
        }
      } else if ('+-×÷'.contains(key)) {
        if (endsWithOp(_amount)) {
          _amount = _amount.substring(0, _amount.length - 1) + key;
        } else if (_amount != '0') {
          _amount += key;
        }
      } else {
        if (_amount == '0') {
          _amount = key;
        } else {
          final segment = _amount.split(RegExp(r'[+\-×÷]')).last;
          if (segment.contains('.') && segment.split('.')[1].length >= 2) return;
          _amount += key;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final categories = _isExpense ? expenseCategories : incomeCategories;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          backgroundColor: themeColor,
          foregroundColor: colorTextOnPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '',
            onPressed: () => Navigator.pop(context),
          ),
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: SizedBox(
                width: 144,
                height: 4,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      left: _isExpense ? 0.0 : 72.0,
                      top: 0,
                      child: Container(
                        width: 72,
                        height: 3,
                        decoration: BoxDecoration(
                          color: colorTextOnPrimary,
                          borderRadius: BorderRadius.circular(radiusTiny),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() {
                    _isExpense = true;
                    _selectedCategory = 0;
                  }),
                  child: SizedBox(
                    width: 72,
                    height: 36,
                    child: Center(
                      child: Text(
                        '支出',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: _isExpense ? FontWeight.w600 : FontWeight.w400,
                          color: colorTextOnPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    _isExpense = false;
                    _selectedCategory = 0;
                  }),
                  child: SizedBox(
                    width: 72,
                    height: 36,
                    child: Center(
                      child: Text(
                        '收入',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: !_isExpense ? FontWeight.w600 : FontWeight.w400,
                          color: colorTextOnPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(spacingL, 0, spacingL, 0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: spacingM,
                  crossAxisSpacing: spacingM,
                  childAspectRatio: 1,
                ),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final selected = _selectedCategory == index;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = index),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: sizeCategoryCircle,
                            height: sizeCategoryCircle,
                            decoration: BoxDecoration(
                              color: selected ? themeColor : const Color(0xFFDDDDDD),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              cat.icon,
                              size: iconSizeXLarge,
                              color: selected ? colorTextOnPrimary : const Color(0xFF555555),
                            ),
                          ),
                          const SizedBox(height: spacingXS),
                          Text(
                            cat.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: selected ? themeColor : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const Divider(height: 1, thickness: borderWidthThin, color: colorBorderKeyboard),
          Container(
            height: heightOptionBar,
            padding: const EdgeInsets.symmetric(horizontal: spacingL),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _remarkController,
                    maxLength: 20,
                    style: textBody,
                    cursorColor: Theme.of(context).extension<AppThemeColors>()!.primary,
                    decoration: const InputDecoration(
                      hintText: '备注',
                      hintStyle: TextStyle(fontSize: 14, color: Color(0xFF6F6F6F)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                    ),
                  ),
                ),
                Text(
                  endsWithOp(_amount)
                      ? _amount
                      : _amount.contains(RegExp(r'[+\-×÷]'))
                          ? '$_amount = ${evaluate(_amount)}'
                          : _amount,
                  style: textAmountInput.copyWith(color: themeColor),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: borderWidthThin, color: colorBorderKeyboard),
          _buildOptionBar(),
          const Divider(height: 1, thickness: borderWidthThin, color: colorBorderKeyboard),
          _buildKeyboard(),
        ],
      ),
    );
  }

  String _formatSelectedDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    if (selected == today) return '今天';
    return '${_selectedDate.month}月${_selectedDate.day}日';
  }

  Widget _buildOptionBar() {
    return Container(
      height: heightOptionBar,
      padding: const EdgeInsets.symmetric(horizontal: spacingL),
      child: Row(
        children: [
          _buildOptionItem(
            icon: Icons.calendar_today_outlined,
            label: _formatSelectedDate(),
            onTap: () async {
              final picked = await showDatePickerSheet(context, _selectedDate);
              if (picked != null) setState(() => _selectedDate = picked);
            },
          ),
          const SizedBox(width: spacingXXL),
          _buildOptionItem(
            icon: Icons.account_balance_wallet_outlined,
            label: _selectedAccount?.name ?? '账户',
            onTap: _pickAccount,
          ),
          const SizedBox(width: spacingXXL),
          // TODO: 接入标签功能（关联 tags 表）
          _buildOptionItem(
            icon: Icons.label_outline,
            label: '标签',
            onTap: () => showToast(context, '标签功能开发中'),
          ),
          const SizedBox(width: spacingXXL),
          // TODO: 接入图片附件功能
          _buildOptionItem(
            icon: Icons.camera_alt_outlined,
            label: '图片',
            onTap: () => showToast(context, '图片附件功能开发中'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAccount() async {
    final accounts = await loadAssetAccounts();
    if (!mounted) return;
    final result = await showAccountPicker(
      context,
      accounts: accounts,
      selectedId: _selectedAccount?.id,
    );
    if (result == null || !mounted) return;
    if (result == noAccountSelection) {
      setState(() => _selectedAccount = null);
      return;
    }
    if (result is AssetAccount) {
      setState(() => _selectedAccount = result);
    }
  }

  Widget _buildOptionItem({required IconData icon, required String label, required VoidCallback onTap}) {    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSizeMedium, color: colorTextPrimary),
          const SizedBox(width: spacingXS),
          Text(label, style: textSecondary.copyWith(fontSize: 14, color: colorTextPrimary)),
        ],
      ),
    );
  }

  Widget _buildKeyboard() {
    return Container(
      color: colorBackgroundCard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildKeyboardRow(['7', '8', '9'], _buildBackspace()),
          _buildDivider(),
          _buildKeyboardRow(['4', '5', '6'], _buildOpsPair('+', '-')),
          _buildDivider(),
          _buildKeyboardRow(['1', '2', '3'], _buildOpsPair('×', '÷')),
          _buildDivider(),
          _buildKeyboardRow(['.', '0', '再记'], _buildDone()),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const SizedBox(
      height: 1,
      child: Divider(height: 1, thickness: borderWidthThin, color: colorBorderKeyboard),
    );
  }

  Widget _buildKeyboardRow(List<String> keys, Widget trailing) {
    return Row(
      children: [
        ...keys.map((key) => Expanded(child: _buildKey(key))),
        Expanded(child: trailing),
      ],
    );
  }

  Widget _buildKey(String key) {
    return GestureDetector(
      onTap: () => _onKeyPressed(key),
      child: Container(
        height: heightKeyboardRow,
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: colorBorderKeyboard, width: borderWidthThin),
          ),
        ),
        alignment: Alignment.center,
        child: _buildKeyChild(key),
      ),
    );
  }

  Widget _buildBackspace() {
    return GestureDetector(
      onTap: () => _onKeyPressed('⌫'),
      child: Container(
        height: heightKeyboardRow,
        alignment: Alignment.center,
        child: const Text(
          '⌫',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: colorTextPrimary),
        ),
      ),
    );
  }

  Widget _buildOpsPair(String a, String b) {
    return Row(
      children: [
        Expanded(child: _buildKey(a)),
        Expanded(child: _buildKey(b)),
      ],
    );
  }

  Widget _buildDone() {
    return GestureDetector(
      onTap: () => _onKeyPressed('完成'),
      child: Container(
        height: heightKeyboardRow,
        color: Theme.of(context).extension<AppThemeColors>()!.primary,
        alignment: Alignment.center,
        child: const Text(
          '完成',
          style: textButtonPrimary,
        ),
      ),
    );
  }

  Widget _buildKeyChild(String key) {
    if (key == '再记') {
      return const Text(
        '再记',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: colorTextPrimary),
      );
    }
    return Text(
      key,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: colorTextPrimary,
      ),
    );
  }
}
