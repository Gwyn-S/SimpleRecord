import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/category.dart';
import '../../services/core/theme_service.dart';
import '../../services/data/category_service.dart';
import '../../utils/toast.dart';
import '../../widgets/common/tab_switcher_app_bar.dart';
import 'category_edit_page.dart';

class CategoryManagePage extends StatefulWidget {
  const CategoryManagePage({super.key});

  @override
  State<CategoryManagePage> createState() => _CategoryManagePageState();
}

class _CategoryManagePageState extends State<CategoryManagePage> {
  bool _isExpense = true;
  late List<Category> _categories;

  @override
  void initState() {
    super.initState();
    _categories = List.of(expenseCategories);
  }

  void _switchTab(bool isExpense) {
    setState(() {
      _isExpense = isExpense;
      _categories = List.of(
        isExpense ? expenseCategories : incomeCategories,
      );
    });
  }

  Future<void> _reload() async {
    await loadCategoryCache();
    if (!mounted) return;
    setState(() {
      _categories = List.of(
        _isExpense ? expenseCategories : incomeCategories,
      );
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final moved = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, moved);
    });
    reorderCategories(_categories);
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text('确定删除分类「$name」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: colorDelete)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removed = await deleteCategory(name: name, isExpense: _isExpense);
    if (mounted && removed > 0) {
      safeShowToast(context, '已删除「$name」及其 $removed 条记录');
    }
    await _reload();
  }

  Future<void> _openEditPage() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryEditPage(isExpense: _isExpense),
      ),
    );
    if (saved == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      backgroundColor: colorBackgroundPage,
      appBar: TabSwitcherAppBar(
        tabs: const ['支出', '收入'],
        selectedIndex: _isExpense ? 0 : 1,
        onChanged: (i) => _switchTab(i == 0),
        backgroundColor: themeColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 28),
            onPressed: _openEditPage,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              color: colorBackgroundCard,
              child: Column(
                children: [
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _categories.length,
                    onReorderItem: _onReorder,
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isLast = index == _categories.length - 1;
                      return Container(
                        key: ValueKey(cat.name),
                        decoration: BoxDecoration(
                          border: isLast
                              ? null
                              : const Border(
                                  bottom: BorderSide(color: colorDivider),
                                ),
                        ),
                        child: ReorderableDelayedDragStartListener(
                          index: index,
                          child: Container(
                            height: 54,
                            padding: const EdgeInsets.symmetric(
                              horizontal: spacingL,
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _delete(cat.name),
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                      color: colorDelete,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.remove,
                                      size: 16,
                                      color: colorTextOnPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: spacingS),
                                Container(
                                  width: sizeCategoryCircle,
                                  height: sizeCategoryCircle,
                                  decoration: const BoxDecoration(
                                    color: colorIconLightBackground,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    cat.icon,
                                    size: iconSizeXLarge,
                                    color: colorIconGray,
                                  ),
                                ),
                                const SizedBox(width: spacingS),
                                Expanded(
                                  child: Text(cat.name, style: textBody),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Container(height: 1, color: colorDivider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}