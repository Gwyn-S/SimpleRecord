import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../models/ledger.dart';
import '../services/record_service.dart';
import '../services/ledger_service.dart';
import '../utils/formatters.dart';
import '../utils/id.dart';
import '../utils/toast.dart';

class LedgerListPage extends StatefulWidget {
  const LedgerListPage({super.key});

  @override
  State<LedgerListPage> createState() => _LedgerListPageState();
}

class _LedgerListPageState extends State<LedgerListPage> {
  final List<Ledger> _ledgers = [];
  Map<String, LedgerStats> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadLedgers();
    currentLedgerId.addListener(_onLedgerChanged);
    recordsVersion.addListener(_onLedgerChanged);
  }

  @override
  void dispose() {
    currentLedgerId.removeListener(_onLedgerChanged);
    recordsVersion.removeListener(_onLedgerChanged);
    super.dispose();
  }

  void _onLedgerChanged() {
    _loadStats();
    setState(() {});
  }

  Future<void> _loadLedgers() async {
    try {
      await ensureCurrentLedgerId();
      final loaded = await loadLedgers();
      if (!mounted) return;
      setState(() => _ledgers.addAll(loaded));
      _loadStats();
    } catch (_) {
      // 加载失败保持空列表，等待下次进入页面重试
    }
  }

  Future<void> _loadStats() async {
    final stats = await loadLedgerStats();
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  void _showAddDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(spacingXL, spacingXL, spacingXL, spacingS),
        actionsPadding: const EdgeInsets.fromLTRB(spacingL, 0, spacingL, spacingS),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '请输入账本名称',
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
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final ledger = Ledger(id: genId(), name: name);
                setState(() => _ledgers.add(ledger));
                await insertLedger(ledger);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(int index) {
    final controller = TextEditingController(text: _ledgers[index].name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(spacingXL, spacingXL, spacingXL, spacingS),
        actionsPadding: const EdgeInsets.fromLTRB(spacingL, 0, spacingL, spacingS),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '请输入账本名称',
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
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() => _ledgers[index].name = name);
                await updateLedger(_ledgers[index]);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(int index) {
    if (_ledgers.length <= 1) {
      showToast(context, '至少保留一个账本');
      return;
    }
    final isCurrent = currentLedgerId.value == _ledgers[index].id;
    if (isCurrent) {
      showToast(context, '正在使用的账本无法删除');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账本'),
        content: Text('确定删除「${_ledgers[index].name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final deletedId = _ledgers[index].id;
              setState(() => _ledgers.removeAt(index));
              await deleteLedger(deletedId);
              if (context.mounted) Navigator.pop(context);
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          title: const Text('账本'),
          backgroundColor: themeColor,
          foregroundColor: colorTextOnPrimary,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: colorTextOnPrimary.withValues(alpha: 0.3), height: 1),
          ),
          leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: '', onPressed: () => Navigator.pop(context)),
          actions: [
            IconButton(
              icon: const Icon(Icons.add, size: 28),
              onPressed: _showAddDialog,
            ),
          ],
        ),
      ),
      body: _ledgers.isEmpty
          ? const Center(child: Text('暂无账本，点击右上角 + 新建', style: TextStyle(color: colorTextPlaceholder)))
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _ledgers.length,
              separatorBuilder: (_, _) => Container(
                height: 1,
                color: colorDivider,
              ),
              itemBuilder: (context, index) {
                final ledger = _ledgers[index];
                final isCurrent = currentLedgerId.value == ledger.id;
                final stats = _stats[ledger.id];
                final count = stats?.count ?? 0;
                final income = stats?.income ?? 0;
                final expense = stats?.expense ?? 0;
                return GestureDetector(
                  onTap: () {
                    saveCurrentLedgerId(ledger.id);
                    Navigator.pop(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(spacingL, 10, spacingL, 10),
                    child: SizedBox(
                      height: 100,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Column(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 80,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: themeColor,
                                    borderRadius: BorderRadius.circular(radiusSmall),
                                  ),
                                  child: Center(
                                    child: Text(
                                      ledger.name,
                                      style: textCardTitle,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (isCurrent)
                                  const Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Icon(Icons.check, color: colorTextOnPrimary, size: iconSizeSmall),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(width: spacingL),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('记录数：$count', style: textCardMeta),
                              const SizedBox(height: spacingXS),
                              Text('总收入：${formatAmount(income)}', style: textCardMeta),
                              const SizedBox(height: spacingXS),
                              Text('总支出：${formatAmount(expense)}', style: textCardMeta),
                              const SizedBox(height: spacingXS),
                              Text('总结余：${formatAmount(income - expense)}', style: textCardMeta),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 100,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _showEditDialog(index),
                                  child: Icon(Icons.edit, size: 30, color: themeColor),
                                ),
                                const SizedBox(width: spacingL),
                                GestureDetector(
                                  onTap: () => _showDeleteDialog(index),
                                  child: Icon(Icons.delete_outline, size: 30, color: themeColor),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
