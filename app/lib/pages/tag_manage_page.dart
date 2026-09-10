import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/tag.dart';
import '../services/tag_service.dart';
import '../services/theme_service.dart';
import '../widgets/common_app_bar.dart';

class TagManagePage extends StatefulWidget {
  const TagManagePage({super.key});

  @override
  State<TagManagePage> createState() => _TagManagePageState();
}

class _TagManagePageState extends State<TagManagePage> {
  List<Tag> _tags = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tags = await loadTags();
    if (!mounted) return;
    setState(() => _tags = tags);
  }

  void _showInputDialog({String? editing}) {
    final controller = TextEditingController(text: editing ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
          decoration: InputDecoration(
            hintText: editing == null ? '请输入标签名称' : '请输入新名称',
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
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              final name = controller.text.trim();
              if (name.isEmpty) return;
              if (editing == null) {
                await insertTag(name);
              } else {
                await renameTag(editing, name);
              }
              if (context.mounted) Navigator.pop(context);
              await _load();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text('确定删除「$name」吗？相关记录的标签会被清空。'),
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
    await deleteTag(name);
    await _load();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final moved = _tags.removeAt(oldIndex);
      _tags.insert(newIndex, moved);
    });
    reorderTags(_tags);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      backgroundColor: colorBackgroundPage,
      appBar: const CommonAppBar(title: '标签管理'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              color: colorBackgroundCard,
              child: Column(
                children: [
                  if (_tags.isNotEmpty) ...[
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _tags.length,
                      onReorderItem: _onReorder,
                      buildDefaultDragHandles: false,
                      itemBuilder: (context, index) {
                        final tag = _tags[index];
                        final isLast = index == _tags.length - 1;
                        return Container(
                          key: ValueKey(tag.id),
                          decoration: BoxDecoration(
                            border: isLast
                                ? null
                                : const Border(
                                    bottom: BorderSide(color: colorDivider),
                                  ),
                          ),
                          child: ReorderableDelayedDragStartListener(
                            index: index,
                            child: GestureDetector(
                              onTap: () => _showInputDialog(editing: tag.name),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: spacingL,
                                  vertical: spacingS,
                                ),
                                child: Row(
                                  children: [
                                    // 左侧红底减号删除按钮
                                    GestureDetector(
                                      onTap: () => _delete(tag.name),
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
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
                                    Expanded(
                                      child: Text(tag.name, style: textBody),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // 最后一个标签下方的细线
                    Container(height: 1, color: colorDivider),
                  ],
                ],
              ),
            ),
            _buildBottomBar(themeColor),
          ],
        ),
      ),
    );
  }

  /// 排序提示 + 新增标签按钮（账单页背景色）。
  Widget _buildBottomBar(Color themeColor) {
    return Container(
      color: colorBackgroundPage,
      padding: const EdgeInsets.fromLTRB(
        spacingL,
        spacingS,
        spacingL,
        spacingS,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('长按拖曳排序标签列表', style: textHint),
          const SizedBox(height: spacingS),
          GestureDetector(
            onTap: () => _showInputDialog(),
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: themeColor,
                borderRadius: BorderRadius.circular(radiusTiny),
              ),
              child: Text(
                '新增标签',
                style: TextStyle(fontSize: 15, color: colorTextOnPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
