import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../pages/tag_manage_page.dart';
import '../models/tag.dart';
import '../services/tag_service.dart';
import '../services/theme_service.dart';

/// 弹窗关闭时代表"清除标签"的哨兵值。
const String noTagSelection = '__no_tag__';

/// 标签选择弹窗：搜索/创建 + 网格单选（点当前选中项为清除）+ 清除按钮。
/// 创建标签后不自动选中，仅刷新列表。
/// 返回选中的标签名、[noTagSelection]（清除）或 null（未操作）。
Future<String?> showTagPickerSheet(BuildContext context, {String? selected}) {
  return showDialog<String>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: colorBackgroundCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      child: _TagPickerSheet(selected: selected),
    ),
  );
}

class _TagPickerSheet extends StatefulWidget {
  final String? selected;

  const _TagPickerSheet({this.selected});

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final _controller = TextEditingController();
  List<Tag> _tags = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tags = await loadTags();
    if (!mounted) return;
    setState(() => _tags = tags);
  }

  void _pick(String name) => Navigator.pop(context, name);

  /// 创建标签后不自动选择，清空搜索框并刷新列表。
  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    await insertTag(name);
    _controller.clear();
    await _load();
  }

  Future<void> _openManage() async {
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TagManagePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final q = _controller.text.trim();
    final filtered = q.isEmpty
        ? _tags
        : _tags.where((t) => t.name.contains(q)).toList();
    // 搜索词非空且没有完全匹配的标签时，才显示创建横条
    final hasCreateEntry = q.isNotEmpty && !filtered.any((t) => t.name == q);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        spacingL,
        spacingM,
        spacingL,
        spacingS,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: spacingS),
                  decoration: BoxDecoration(
                    color: colorBackgroundInput,
                    borderRadius: BorderRadius.circular(radiusMedium),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search,
                        size: 20,
                        color: colorTextSecondary,
                      ),
                      const SizedBox(width: spacingXS),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: textBody,
                          decoration: const InputDecoration(
                            hintText: '输入搜索或创建标签',
                            hintStyle: textHint,
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: spacingS),
              GestureDetector(
                onTap: _openManage,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  '管理',
                  style: TextStyle(fontSize: 14, color: themeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: spacingM),
          if (hasCreateEntry) ...[
            _buildCreateBar(themeColor, q),
            const SizedBox(height: spacingS),
          ],
          SizedBox(
            height: 320,
            child: filtered.isEmpty && q.isEmpty
                ? const SizedBox.shrink()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final cellWidth =
                          (constraints.maxWidth - spacingS * 2) / 3;
                      return GridView.count(
                        crossAxisCount: 3,
                        // 格高贴合按钮高度（约34），避免行间留白过大
                        childAspectRatio: cellWidth / 36,
                        mainAxisSpacing: spacingS,
                        crossAxisSpacing: spacingS,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final t in filtered)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _buildTagButton(themeColor, t.name),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          const SizedBox(height: spacingS),
          GestureDetector(
            onTap: () => _pick(noTagSelection),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Text(
                '清除标签',
                style: TextStyle(fontSize: 14, color: colorTextPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagButton(Color themeColor, String name) {
    final selected = widget.selected == name;
    return GestureDetector(
      onTap: () => _pick(selected ? noTagSelection : name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: spacingM, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? themeColor : colorBackgroundInput,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        child: Text(
          name,
          maxLines: 1,
          style: TextStyle(
            fontSize: 14,
            color: selected ? colorTextOnPrimary : colorTextPrimary,
          ),
        ),
      ),
    );
  }

  /// 横条式创建入口：无匹配时显示，点击创建后不自动选中。
  Widget _buildCreateBar(Color themeColor, String q) {
    return GestureDetector(
      onTap: _create,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          horizontal: spacingM,
          vertical: spacingS,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: themeColor, width: 1),
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        child: Text(
          '创建标签"$q"',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, color: themeColor),
        ),
      ),
    );
  }
}
