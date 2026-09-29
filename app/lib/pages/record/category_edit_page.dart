import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/category.dart';
import '../../services/core/theme_service.dart';
import '../../services/data/category_service.dart';
import '../../utils/toast.dart';

/// 新增分类页：输入名称 + 选择图标。
class CategoryEditPage extends StatefulWidget {
  const CategoryEditPage({super.key, required this.isExpense, this.existing});

  final bool isExpense;

  /// 非空为编辑模式：预填原名称与图标，保存时改名 + 换图标。
  final Category? existing;

  @override
  State<CategoryEditPage> createState() => _CategoryEditPageState();
}

/// 可选图标：排除「设置」入口专用图标。
final List<String> _selectableIcons = categoryIconMap.keys
    .where((k) => k != 'settings_outlined')
    .toList();

class _CategoryEditPageState extends State<CategoryEditPage> {
  late final TextEditingController _nameController;
  late String _iconName;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    final current = existing?.iconName ?? '';
    _iconName = _selectableIcons.contains(current)
        ? current
        : _selectableIcons.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isEditing) {
      await _saveEdit();
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final ok = await insertCategory(name: name, isExpense: widget.isExpense, iconName: _iconName);
    if (!mounted) return;
    if (!ok) {
      safeShowToast(context, '该分类已存在');
      setState(() => _saving = false);
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _saveEdit() async {
    final old = widget.existing!;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);

    if (name != old.name) {
      final renamed = await renameCategory(old.name, name, old.isExpense);
      if (!mounted) return;
      if (!renamed) {
        safeShowToast(context, '该分类已存在');
        setState(() => _saving = false);
        return;
      }
    }
    if (_iconName != old.iconName) {
      await updateCategoryIcon(
        name: name,
        isExpense: old.isExpense,
        iconName: _iconName,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      backgroundColor: colorBackgroundPage,
      appBar: AppBar(
        title: Text(_isEditing ? '编辑分类' : '新增分类'),
        backgroundColor: Theme.of(context).extension<AppThemeColors>()!.primary,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: spacingS),
            child: TextButton(
              onPressed: _saving ? null : _save,
              style: TextButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: colorTextOnPrimary,
                disabledForegroundColor: colorTextOnPrimary.withValues(
                  alpha: 0.5,
                ),
                shape: const RoundedRectangleBorder(),
                overlayColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: spacingM,
                  vertical: 8,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('保存', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colorBackgroundCard,
            padding: const EdgeInsets.fromLTRB(
              spacingL,
              spacingS,
              spacingL,
              spacingS,
            ),
            child: Column(
              children: [
                Container(
                  width: sizeCategoryCircle,
                  height: sizeCategoryCircle,
                  decoration: const BoxDecoration(
                    color: colorIconLightBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    categoryIconMap[_iconName] ?? Icons.help_outline,
                    size: iconSizeXLarge,
                    color: colorIconGray,
                  ),
                ),
                const SizedBox(height: spacingM),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: textBody,
                    decoration: InputDecoration(
                      hintText: '请输入分类',
                      hintStyle: textHint,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: spacingXS,
                      ),
                      border: InputBorder.none,
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: colorTextSecondary),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: themeColor),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 40,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: spacingL),
            color: colorBackgroundPage,
            child: Text('请选择分类图标', style: textBody),
          ),
          Expanded(
            child: Container(
              color: colorBackgroundCard,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final innerWidth = constraints.maxWidth - spacingL * 2;
                  final itemWidth = (innerWidth - spacingM * 3) / 4;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(spacingL),
                    child: Wrap(
                      spacing: spacingM,
                      runSpacing: spacingS,
                      children: [
                        for (final iconName in _selectableIcons)
                          SizedBox(
                            width: itemWidth,
                            height: 56,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _iconName = iconName),
                              child: Center(
                                child: Container(
                                  width: sizeCategoryCircle,
                                  height: sizeCategoryCircle,
                                  decoration: BoxDecoration(
                                    color: _iconName == iconName
                                        ? themeColor
                                        : colorIconLightBackground,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    categoryIconMap[iconName]!,
                                    size: iconSizeXLarge,
                                    color: _iconName == iconName
                                        ? colorTextOnPrimary
                                        : colorIconGray,
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
            ),
          ),
        ],
      ),
    );
  }
}