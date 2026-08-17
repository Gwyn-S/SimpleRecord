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
import '../widgets/calc_keyboard.dart';
import '../widgets/date_picker_sheet.dart';
import '../widgets/tag_picker_sheet.dart';

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
  String? _selectedTag;
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
      _selectedTag = r.tag;
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
    if (_selectedCategory == null) return '其他';
    return cats[_selectedCategory!].name;
  }

  Future<bool> _saveRecord() async {
    final result = evaluate(_amount);
    final parsed = double.tryParse(result);
    if (parsed == null) {
      _showMessage('金额无效');
      return false;
    }
    if (parsed < 0) {
      _showMessage('金额不能为负');
      return false;
    }
    final amountCents = yuanToCents(result);
    if (amountCents == 0) {
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
      tag: _selectedTag,
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
                padding: const EdgeInsets.only(bottom: spacingM),
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
                              color: selected ? themeColor : colorIconLightBackground,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              cat.icon,
                              size: iconSizeXLarge,
                              color: selected ? colorTextOnPrimary : colorIconGray,
                            ),
                          ),
                          const SizedBox(height: spacingXS),
                          Text(
                            cat.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: selected ? themeColor : colorTextPrimary,
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
                    decoration: InputDecoration(
                      hintText: '备注',
                      hintStyle: TextStyle(fontSize: 14, color: colorTextHintLight),
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
                          ? '$_amount=${evaluate(_amount)}'
                          : _amount,
                  style: textAmountInput.copyWith(color: themeColor),
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
            extraLabel: '再记',
            onExtra: () {
              _saveRecord().then((ok) {
                if (!ok || !mounted) return;
                setState(() {
                  _amount = '0';
                  _remarkController.clear();
                  _selectedCategory = 0;
                  _selectedAccount = null;
                });
              });
            },
            onDone: () {
              _saveRecord().then((ok) {
                if (ok && context.mounted) Navigator.pop(context);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOptionBar() {
    return Container(
      height: heightOptionBar,
      padding: const EdgeInsets.symmetric(horizontal: spacingL),
      child: Row(
        children: [
          _buildOptionItem(
            icon: Icons.calendar_today_outlined,
            label: formatSelectedDate(_selectedDate),
            onTap: () async {
              final picked = await showDatePickerSheet(context, _selectedDate);
              if (picked == null || !mounted) return;
              setState(() => _selectedDate = picked);
            },
          ),
          const SizedBox(width: spacingXXL),
          _buildOptionItem(
            icon: Icons.account_balance_wallet_outlined,
            label: _selectedAccount?.name ?? '账户',
            onTap: _pickAccount,
          ),
          const SizedBox(width: spacingXXL),
          // 标签：单标签，选择后回填
          _buildOptionItem(
            icon: Icons.label_outline,
            label: _selectedTag ?? '标签',
            onTap: _pickTag,
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

  Future<void> _pickTag() async {
    final result = await showTagPickerSheet(context, selected: _selectedTag);
    if (result == null || !mounted) return;
    setState(() {
      _selectedTag = result == noTagSelection ? null : result;
    });
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
}

