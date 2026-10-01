import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../services/core/theme_service.dart';
import '../../models/data/category.dart';
import '../../models/data/record.dart';
import '../../models/data/asset_account.dart';
import '../../services/data/record_service.dart';
import '../../services/data/asset_account_service.dart';
import '../../services/image/image_storage_service.dart';
import '../../utils/calculator.dart';
import '../../utils/formatters.dart';
import '../../utils/navigation.dart';
import '../../widgets/common/option_bar_item.dart';
import '../../utils/id.dart';
import '../../utils/toast.dart';
import '../../widgets/record/account_picker_sheet.dart';
import '../../widgets/record/calc_keyboard.dart';
import '../../widgets/common/date_picker_sheet.dart';
import '../../widgets/common/full_image_viewer.dart';
import '../../widgets/common/tab_switcher_app_bar.dart';
import '../../widgets/record/tag_picker_sheet.dart';

/// 选项栏固定按五等分切：4 个固定项 + 1 个图片位。
const int _kOptionSlots = 5;

class AddRecordPage extends StatefulWidget {
  final Record? initialRecord;
  const AddRecordPage({super.key, this.initialRecord});

  @override
  State<AddRecordPage> createState() => _AddRecordPageState();
}

class _AddRecordPageState extends State<AddRecordPage> {
  bool _isExpense = true;
  int? _selectedCategory = 0;
  String _amount = '0';
  DateTime _selectedDate = DateTime.now();
  AssetAccount? _selectedAccount;
  String? _selectedTag;
  final _remarkController = TextEditingController();
  List<String> _imagePaths = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecord;
    if (r != null) {
      _isExpense = r.isExpense;
      final cats = r.isExpense ? expenseCategories : incomeCategories;
      final idx = cats.indexWhere((c) => c.name == r.categoryName);
      _selectedCategory = idx >= 0 ? idx : null;
      _amount = formatAmountEdit(r.amountCents);
      _selectedDate = r.date;
      _remarkController.text = r.remark;
      _selectedTag = r.tag;
      _imagePaths = r.imagePaths ?? [];
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
    final (amountCents, amountError) = parseAmountCents(_amount);
    if (amountError != null) {
      safeShowToast(context, amountError);
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
      imagePaths: _imagePaths,
    );
    if (origin != null) {
      await updateRecord(record);
    } else {
      await insertRecord(record);
    }
    return true;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        final saved = await saveImage(image.path);
        setState(() => _imagePaths.add(saved));
      }
    } catch (e) {
      if (mounted) {
        safeShowToast(context, '选择图片失败');
      }
    }
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              title: const Text('相册'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final categories = _isExpense ? expenseCategories : incomeCategories;
    return Scaffold(
      appBar: TabSwitcherAppBar(
        tabs: const ['支出', '收入'],
        selectedIndex: _isExpense ? 0 : 1,
        onChanged: (i) => setState(() {
          _isExpense = i == 0;
          _selectedCategory = 0;
        }),
        backgroundColor: themeColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                itemCount: categories.length + 1,
                itemBuilder: (context, index) {
                  final isSettings = index == categories.length;
                  final cat = isSettings
                      ? const Category(
                          name: '设置',
                          isExpense: false,
                          iconName: 'settings_outlined',
                        )
                      : categories[index];
                  final selected = _selectedCategory == index;
                  return GestureDetector(
                    onTap: () {
                      if (isSettings) {
                        openCategoryManage(context);
                        return;
                      }
                      setState(() => _selectedCategory = index);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: sizeCategoryCircle,
                            height: sizeCategoryCircle,
                            decoration: BoxDecoration(
                              color: isSettings
                                  ? themeColor.withValues(alpha: 0.15)
                                  : selected
                                  ? themeColor
                                  : colorIconLightBackground,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              cat.icon,
                              size: iconSizeXLarge,
                              color: isSettings
                                  ? themeColor
                                  : selected
                                  ? colorTextOnPrimary
                                  : colorIconGray,
                            ),
                          ),
                          const SizedBox(height: spacingXS),
                          Text(
                            cat.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: isSettings
                                  ? themeColor
                                  : selected
                                  ? themeColor
                                  : colorTextPrimary,
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
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorBorderKeyboard,
          ),
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
                    cursorColor: Theme.of(
                      context,
                    ).extension<AppThemeColors>()!.primary,
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
                Text(
                  amountPreview(_amount),
                  style: textAmountInput.copyWith(color: themeColor),
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
            extraLabel: '再记',
            onExtra: () {
              FocusManager.instance.primaryFocus?.unfocus();
              _saveRecord().then((ok) {
                if (!ok || !mounted) return;
                setState(() {
                  _amount = '0';
                  _remarkController.clear();
                  _selectedTag = null;
                  _imagePaths = [];
                });
              });
            },
            onDone: () {
              FocusManager.instance.primaryFocus?.unfocus();
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
    return SizedBox(
      height: heightOptionBar,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 固定五等分：4 个固定项各占可视宽度的 1/5；图片宽度另算，排在后面。
          final cell = constraints.maxWidth / _kOptionSlots;
          // 文字偏长时允许超出 1/5 自适应扩宽，避免被压缩变小。
          final dateLabel = formatSelectedDate(_selectedDate);

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                OptionBarItem(
                  width: _fitCell(dateLabel, cell),
                  icon: Icons.calendar_today_outlined,
                  label: dateLabel,
                  onTap: () async {
                    final picked = await showDatePickerSheet(
                      context,
                      _selectedDate,
                    );
                    if (picked == null || !mounted) return;
                    setState(() => _selectedDate = picked);
                  },
                ),
                OptionBarItem(
                  width: _fitCell(_selectedAccount?.name ?? '无账户', cell),
                  icon: Icons.account_balance_wallet_outlined,
                  label: _selectedAccount?.name ?? '无账户',
                  onTap: _pickAccount,
                ),
                OptionBarItem(
                  width: _fitCell(_selectedTag ?? '标签', cell),
                  icon: Icons.label_outline,
                  label: _selectedTag ?? '标签',
                  onTap: _pickTag,
                ),
                OptionBarItem(
                  width: _fitCell('图片', cell),
                  icon: Icons.camera_alt_outlined,
                  label: '图片',
                  onTap: _showImagePicker,
                ),
                if (_imagePaths.isNotEmpty)
                  ...List.generate(
                    _imagePaths.length,
                    (index) => GestureDetector(
                      onTap: () => _showImageViewer(index),
                      child: SizedBox(
                        width: 32,
                        height: heightOptionBar,
                        child: Center(
                          child: Image.file(
                            File(_imagePaths[index]),
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 选项格宽度：默认取 1/5 固定份，文字放不下时按实际所需自适应扩大。
  double _fitCell(String label, double cell) {
    final needed = OptionBarItem.measureWidth(label);
    return needed > cell ? needed : cell;
  }

  void _showImageViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullImageViewer(
          imagePaths: _imagePaths,
          initialIndex: index,
          onDelete: (i) {
            final path = _imagePaths[i];
            setState(() => _imagePaths.removeAt(i));
            deleteImage(path);
            Navigator.pop(context);
          },
        ),
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
}
