import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../models/ledger.dart';
import '../services/record_service.dart';
import '../services/ledger_service.dart';
import '../utils/formatters.dart';
import '../utils/id.dart';
import '../widgets/common_app_bar.dart';
import '../utils/toast.dart';
import '../services/cloud_config.dart';
import '../services/settings.dart';
import '../services/sync_service.dart';

class LedgerListPage extends StatefulWidget {
  const LedgerListPage({super.key});

  @override
  State<LedgerListPage> createState() => _LedgerListPageState();
}

class _LedgerListPageState extends State<LedgerListPage> {
  final List<Ledger> _ledgers = [];
  Map<String, LedgerStats> _stats = {};
  Map<String, Map<String, int>> _perAuthor = {};

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
      setState(() {
        _ledgers
          ..clear()
          ..addAll(loaded);
      });
      _loadStats();
      SyncService.instance.precacheInviteCodes(
        _ledgers.where((l) => l.syncMode == 1).map((l) => l.id),
      );
    } catch (_) {
      if (mounted) safeShowToast(context, '加载账本失败，请重试');
    }
  }

  Future<void> _loadStats() async {
    final results = await Future.wait([
      loadLedgerStats(),
      loadLedgerPerAuthorBalance(),
    ]);
    if (!mounted) return;
    setState(() {
      _stats = results[0] as Map<String, LedgerStats>;
      _perAuthor = results[1] as Map<String, Map<String, int>>;
    });
  }

  /// 多人账本结余行：总结余 + 按作者分组，如「总结余：-17.00 A：-8.00 B：-9.00」。
  String _sharedBalanceLine(String bookId, int total) {
    final buf = StringBuffer('总结余：${formatAmount(total)}');
    (_perAuthor[bookId] ?? const {}).forEach((author, bal) {
      buf.write(' $author：${formatAmount(bal)}');
    });
    return buf.toString();
  }

void _showAddDialog() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(spacingXL, spacingXL, spacingXL, spacingS),
        actionsPadding: const EdgeInsets.fromLTRB(spacingL, 0, spacingL, spacingS),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '账本名称',
                border: InputBorder.none,
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).extension<AppThemeColors>()!.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: spacingS),
            TextField(
              controller: codeController,
              decoration: InputDecoration(
                labelText: '邀请码',
                border: InputBorder.none,
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).extension<AppThemeColors>()!.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final code = codeController.text.trim().toUpperCase();
              final name = nameController.text.trim();
              if (code.isNotEmpty) {
                final (result, ledger) =
                    await SyncService.instance.joinByInvite(code);
                if (!context.mounted) return;
                Navigator.pop(context);
                switch (result) {
                  case JoinSyncResult.success:
                    await _loadLedgers();
                    if (context.mounted) {
                      showToast(context, '已加入「${ledger!.name}」');
                    }
                  case JoinSyncResult.notReady:
                    showToast(context, '请先到「备份 → Supabase 同步」配置云同步');
                  case JoinSyncResult.roomNotFound:
                    showToast(context, '未找到该邀请码对应的房间，请核对邀请码');
                  case JoinSyncResult.joinFailed:
                    showToast(context, '加入失败：网络异常，或云端匿名登录未开启');
                }
              } else if (name.isNotEmpty) {
                final ledger = Ledger(id: genId(), name: name);
                setState(() => _ledgers.add(ledger));
                await insertLedger(ledger);
                if (context.mounted) Navigator.pop(context);
              } else {
                showToast(context, '请输入账本名称或邀请码');
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
    final inviteCodeFuture = _ledgers[index].syncMode == 1
        ? SyncService.instance.getInviteCode(_ledgers[index].id)
        : Future<String?>.value(null);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(spacingXL, spacingXL, spacingXL, spacingS),
        actionsPadding: const EdgeInsets.fromLTRB(spacingL, 0, spacingL, spacingS),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
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
            const SizedBox(height: spacingS),
            if (_ledgers[index].syncMode == 1)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    tileColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    title: const Text(
                      '多人记账',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: colorTextPrimary,
                      ),
                    ),
                    trailing: Switch(
                      value: true,
                      onChanged: (_) {
                        Navigator.pop(context);
                        _disableShared(index);
                      },
                      activeTrackColor: Theme.of(context).extension<AppThemeColors>()!.primary,
                      inactiveTrackColor: Colors.grey.shade300,
                      thumbColor: WidgetStateProperty.all(Colors.white),
                    ),
                    dense: true,
                  ),
                  FutureBuilder<String?>(
                    future: inviteCodeFuture,
                    builder: (context, snap) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      tileColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      title: const Text(
                        '邀请他人',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: colorTextPrimary,
                        ),
                      ),
                      trailing: Text(
                        snap.data ?? '',
                        style: textCardMeta.copyWith(
                          color: Theme.of(context).extension<AppThemeColors>()!.primary,
                        ),
                      ),
                      dense: true,
                      onTap: () async {
                        final code = snap.data;
                        if (!context.mounted) return;
                        if (code != null) {
                          await Clipboard.setData(ClipboardData(text: code));
                          if (!context.mounted) return;
                          showToast(context, '已复制邀请码 $code');
                        } else {
                          showToast(context, '邀请码获取失败，请检查网络');
                        }
                      },
                    ),
                  ),
                ],
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                tileColor: Colors.transparent,
                splashColor: Colors.transparent,
                hoverColor: Colors.transparent,
                title: const Text(
                  '多人记账',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: colorTextPrimary,
                  ),
                ),
                trailing: Switch(
                  value: false,
                  onChanged: (_) {
                    Navigator.pop(context);
                    _enableShared(index);
                  },
                  activeTrackColor: Theme.of(context).extension<AppThemeColors>()!.primary,
                  inactiveTrackColor: Colors.grey.shade300,
                  thumbColor: WidgetStateProperty.all(Colors.white),
                ),
                dense: true,
              ),
          ],
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

  Future<void> _enableShared(int index) async {
    if (!await _ensureCloudConfigured()) return;
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(spacingXXL),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: spacingL),
              Text('正在开启多人记账', style: textBody),
            ],
          ),
        ),
      ),
    );
    final ok = await SyncService.instance.enableSync(_ledgers[index]);
    if (!mounted) return;
    navigator.pop();
    if (ok) {
      final code = await SyncService.instance.getInviteCode(_ledgers[index].id);
      if (!mounted) return;
      showToast(context, code != null ? '已开启共享，邀请码 $code' : '已开启共享');
    } else {
      showToast(context, '开启共享失败，请检查网络后重试');
    }
    _loadLedgers();
  }

  Future<void> _disableShared(int index) async {
    await SyncService.instance.disableSync(_ledgers[index].id);
    if (!mounted) return;
    showToast(context, '已关闭多人记账');
    _loadLedgers();
  }

  /// 确保先完成「备份 → Supabase 同步」的三项配置：昵称 + URL + anon key。
  Future<bool> _ensureCloudConfigured() async {
    final config = await loadCloudConfig();
    if (!config.isConfigured) {
      if (mounted) showToast(context, '请先到「备份 → Supabase 同步」配置云同步');
      return false;
    }
    final nickname = await Settings.getString('nickname') ?? '';
    if (nickname.trim().isEmpty) {
      if (mounted) showToast(context, '请先在「备份 → Supabase 同步」填写昵称');
      return false;
    }
    return true;
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
      appBar: CommonAppBar(
        title: '账本',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: colorTextOnPrimary.withValues(alpha: 0.3), height: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 28),
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: _ledgers.isEmpty
          ? const SizedBox.shrink()
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
                                if (ledger.syncMode == 1)
                                  const Positioned(
                                    top: 4,
                                    left: 4,
                                    child: Icon(Icons.people, color: colorTextOnPrimary, size: iconSizeSmall),
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
                              Text(ledger.syncMode == 1
                          ? _sharedBalanceLine(ledger.id, income - expense)
                          : '总结余：${formatAmount(income - expense)}',
                      style: textCardMeta),
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
