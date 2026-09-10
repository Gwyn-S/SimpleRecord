import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/asset_account.dart';
import '../models/record.dart';
import '../services/asset_account_service.dart';
import '../services/export_service.dart';
import '../services/record_service.dart';
import '../services/theme_service.dart';
import '../utils/calendar_utils.dart';
import '../utils/formatters.dart';
import '../widgets/account_avatar.dart';
import '../widgets/date_filter_sheet.dart';
import '../utils/navigation.dart';
import '../utils/toast.dart';
import '../widgets/record_item.dart';

class SearchPage extends StatefulWidget {
  /// 预填的账户筛选（null=不限），用于资产详情"账单"入口。
  final String? initialAccountId;

  const SearchPage({super.key, this.initialAccountId});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _flowLabels = ['收支', '收入', '支出'];
  static const _noAccountFilter = '__no_account__';
  static const _allAccountFilter = '__all_accounts__';
  static const _pageSize = 100;

  final _searchController = TextEditingController();
  List<Record> _allRecords = [];
  List<Record> _filtered = [];
  List<AssetAccount> _accounts = [];
  String? _accountFilter; // null=不限
  int? _minAmountCents; // 金额下限（分），null=不限
  int? _maxAmountCents; // 金额上限（分），null=不限
  int _flowFilter = 0; // 0=不限 1=收入 2=支出
  DateTime? _dateStart; // 起始日期（当天 00:00），null=不限
  DateTime? _dateEnd; // 结束日期（当天 23:59:59），null=不限
  String? _datePreset; // 当前生效的快捷范围名（本周/本月…），自定义或不限为 null
  int _page = 1; // 当前页码（1-based）
  bool _busy = false;

  int get _totalPages =>
      _filtered.isEmpty ? 1 : ((_filtered.length - 1) ~/ _pageSize) + 1;

  List<Record> get _pageRecords {
    final start = (_page - 1) * _pageSize;
    if (start >= _filtered.length) return const [];
    final end = (start + _pageSize).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  /// 过滤条件变化：重算结果并回到第 1 页。
  void _applyFilter() {
    _page = 1;
    _filtered = _filterRecords();
  }

  @override
  void initState() {
    super.initState();
    _accountFilter = widget.initialAccountId; // 预填账户筛选
    _load();
    _loadAccounts();
    recordsVersion.addListener(_load);
    currentLedgerId.addListener(_load);
    assetAccountsVersion.addListener(_loadAccounts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    recordsVersion.removeListener(_load);
    currentLedgerId.removeListener(_load);
    assetAccountsVersion.removeListener(_loadAccounts);
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final accounts = await loadAssetAccounts();
    if (!mounted) return;
    setState(() => _accounts = accounts);
  }

  Future<void> _load() async {
    final records = await loadRecords(ledgerId: currentLedgerId.value);
    if (!mounted) return;
    setState(() {
      _allRecords = records;
      _filtered = _filterRecords();
      _page = 1;
    });
  }

  List<Record> _filterRecords() {
    final q = _searchController.text.trim().toLowerCase();
    return _allRecords.where((r) {
      if (_flowFilter == 1 && r.isExpense) return false;
      if (_flowFilter == 2 && !r.isExpense) return false;
      if (_accountFilter == _noAccountFilter) {
        final acc = r.accountId;
        if (acc != null && acc.isNotEmpty) return false;
      } else if (_accountFilter != null && r.accountId != _accountFilter) {
        return false;
      }
      if (_minAmountCents != null && r.amountCents < _minAmountCents!) {
        return false;
      }
      if (_maxAmountCents != null && r.amountCents > _maxAmountCents!) {
        return false;
      }
      if (_dateStart != null && r.date.isBefore(_dateStart!)) return false;
      if (_dateEnd != null && r.date.isAfter(_dateEnd!)) return false;
      if (q.isEmpty) return true;
      return r.categoryName.toLowerCase().contains(q) ||
          r.remark.toLowerCase().contains(q) ||
          (r.tag != null && r.tag!.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _exportCsv() async {
    if (_filtered.isEmpty) {
      showToast(context, '没有可导出的记录');
      return;
    }
    setState(() => _busy = true);
    try {
      final path = await exportCsv(records: _filtered);
      if (mounted) showToast(context, '导出成功：$path');
    } catch (e) {
      if (mounted) showToast(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final income = monthIncome(_filtered);
    final expense = monthExpense(_filtered);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: themeColor,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Expanded(
              child: Container(
                height: 36,
                margin: const EdgeInsets.only(right: spacingL),
                padding: const EdgeInsets.symmetric(horizontal: spacingS),
                decoration: BoxDecoration(
                  color: colorBackgroundCard,
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
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        style: textBody,
                        decoration: const InputDecoration(
                          hintText: '输入分类/备注/标签',
                          hintStyle: textHint,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (_) => setState(_applyFilter),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildFlowFilter(colorTextOnPrimary),
            const SizedBox(width: spacingL),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: spacingL,
              vertical: spacingM,
            ),
            child: Row(
              children: [
                _buildAccountFilter(themeColor),
                const SizedBox(width: spacingL),
                _buildDateFilter(themeColor),
                const SizedBox(width: spacingL),
                _buildAmountFilter(themeColor),
                const Spacer(),
                OutlinedButton(
                  onPressed: _busy ? null : _exportCsv,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: colorTextOnPrimary,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(radiusSmall),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: spacingM),
                    minimumSize: const Size(0, 32),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('导出'),
                ),
              ],
            ),
          ),
          Container(
            color: colorBackgroundSummary,
            padding: const EdgeInsets.symmetric(
              horizontal: spacingL,
              vertical: spacingS,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('记录数 ${_filtered.length}', style: textItemSub),
                const SizedBox(width: spacingM),
                Text('收入：${formatAmount(income)}', style: textItemSub),
                const SizedBox(width: spacingM),
                Text('支出：${formatAmount(expense)}', style: textItemSub),
                const SizedBox(width: spacingM),
                Text(
                  '结余：${formatAmount(income - expense)}',
                  style: textItemSub,
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: colorBackgroundPage,
              child: _filtered.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: spacingL),
                      itemCount: _pageRecords.length,
                      itemBuilder: (context, index) {
                        final r = _pageRecords[index];
                        return Container(
                          color: colorBackgroundCard,
                          child: RecordItem(
                            record: r,
                            showDate: true,
                            onEdit: () => openEditRecord(context, r),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (_filtered.isNotEmpty) _buildPager(themeColor),
        ],
      ),
    );
  }

  /// 分页栏：上一页（左）/ 页码（中）/ 下一页（右），按钮为主题色。
  Widget _buildPager(Color themeColor) {
    final total = _totalPages;
    final canPrev = _page > 1;
    final canNext = _page < total;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 上方灰色细条
        Container(height: 8, color: colorBackgroundPage),
        // 白色分页栏主体
        Container(
          color: colorBackgroundCard,
          padding: const EdgeInsets.fromLTRB(
            spacingL,
            spacingS,
            spacingL,
            spacingS,
          ),
          child: Row(
            children: [
              _pagerButton(
                '上一页',
                themeColor,
                canPrev,
                () => setState(() => _page--),
              ),
              Expanded(
                child: Center(
                  child: Text('当前页码 $_page 共 $total 页', style: textBody),
                ),
              ),
              _pagerButton(
                '下一页',
                themeColor,
                canNext,
                () => setState(() => _page++),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pagerButton(
    String label,
    Color themeColor,
    bool enabled,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        height: 32,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: spacingM),
        decoration: BoxDecoration(
          color: themeColor,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        child: Text(label, style: textPagerButton),
      ),
    );
  }

  /// 账户筛选下拉：不限 + 无账户 + 全部账户（带图标/卡号）。
  Widget _buildAccountFilter(Color themeColor) {
    String selectedName;
    if (_accountFilter == null) {
      selectedName = '账户不限';
    } else if (_accountFilter == _noAccountFilter) {
      selectedName = '无账户';
    } else {
      final match = _accounts.where((a) => a.id == _accountFilter).toList();
      selectedName = match.isEmpty ? '账户不限' : match.first.name;
    }
    return PopupMenuButton<String?>(
      tooltip: '',
      offset: const Offset(0, 30),
      menuPadding: EdgeInsets.zero,
      itemBuilder: (context) => [
        for (final a in _accounts)
          PopupMenuItem<String?>(
            value: a.id,
            height: 36,
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: spacingM),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: AccountAvatar(
                      account: a,
                      size: 18,
                      color: colorTextSecondary,
                    ),
                  ),
                  const SizedBox(width: spacingS),
                  Expanded(
                    child: Text(
                      a.displayName,
                      style: textBody,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_accountFilter == a.id)
                    Icon(Icons.check, size: 18, color: themeColor),
                ],
              ),
            ),
          ),
        PopupMenuItem<String?>(
          value: _noAccountFilter,
          height: 32,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: spacingM),
            child: Row(
              children: [
                // 预留图标宽度，与账户项文字对齐
                const SizedBox(width: 20 + spacingS),
                Text('无账户', style: textBody),
              ],
            ),
          ),
        ),
        PopupMenuItem<String?>(
          value: _allAccountFilter,
          height: 32,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: spacingM),
            child: Row(
              children: [
                const SizedBox(width: 20 + spacingS),
                Text('不限', style: textBody),
              ],
            ),
          ),
        ),
      ],
      onSelected: (v) => setState(() {
        // 不限用哨兵值传递，避免 null value 被 PopupMenuButton 吞掉
        _accountFilter = v == _allAccountFilter ? null : v;
        _applyFilter();
      }),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(selectedName, style: textBody),
          Icon(Icons.arrow_drop_down, color: colorTextPrimary),
        ],
      ),
    );
  }

  /// 金额筛选：点击弹出 ≥/≤ 输入弹窗，不限/确定生效。
  Widget _buildAmountFilter(Color themeColor) {
    String label;
    if (_minAmountCents != null && _maxAmountCents != null) {
      label =
          '金额 ${formatAmountEdit(_minAmountCents!)}~${formatAmountEdit(_maxAmountCents!)}';
    } else if (_minAmountCents != null && _maxAmountCents == null) {
      label = '金额 ≥${formatAmountEdit(_minAmountCents!)}';
    } else if (_minAmountCents == null && _maxAmountCents != null) {
      label = '金额 ≤${formatAmountEdit(_maxAmountCents!)}';
    } else {
      label = '金额不限';
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openAmountFilter,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: textBody),
          Icon(Icons.arrow_drop_down, color: colorTextPrimary),
        ],
      ),
    );
  }

  Future<void> _openAmountFilter() async {
    final minController = TextEditingController(
      text: _minAmountCents != null ? formatAmountEdit(_minAmountCents!) : '',
    );
    final maxController = TextEditingController(
      text: _maxAmountCents != null ? formatAmountEdit(_maxAmountCents!) : '',
    );
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final result = await showDialog<(int?, int?)>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: colorBackgroundCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        child: Padding(
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
              _amountInputRow('金额≥', minController),
              const SizedBox(height: spacingS),
              _amountInputRow('金额≤', maxController),
              const SizedBox(height: spacingM),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context, (null, null)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: spacingM,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorBackgroundInput,
                        borderRadius: BorderRadius.circular(radiusSmall),
                      ),
                      child: const Text(
                        '不限',
                        style: TextStyle(fontSize: 14, color: colorTextPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: spacingS),
                  GestureDetector(
                    onTap: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final min = _parseAmount(minController.text);
                      final max = _parseAmount(maxController.text);
                      Navigator.pop(context, (min, max));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: spacingM,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: themeColor,
                        borderRadius: BorderRadius.circular(radiusSmall),
                      ),
                      child: const Text(
                        '确定',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorTextOnPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null) return; // 取消，保持原筛选
    setState(() {
      _minAmountCents = result.$1;
      _maxAmountCents = result.$2;
      _applyFilter();
    });
  }

  int? _parseAmount(String s) {
    final v = double.tryParse(s.trim());
    if (v == null) return null;
    return (v * 100).round();
  }

  Widget _amountInputRow(String label, TextEditingController controller) {
    return Row(
      children: [
        Text(label, style: textBody),
        const SizedBox(width: spacingM),
        Expanded(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: spacingS),
            decoration: BoxDecoration(
              color: colorBackgroundInput,
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: textBody,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 日期筛选：点击弹出快捷范围 + 自定义起止弹窗。
  Widget _buildDateFilter(Color themeColor) {
    String label;
    if (_datePreset != null) {
      label = _datePreset!;
    } else if (_dateStart != null) {
      label = '${_fmtDate(_dateStart!)} 至 ${_fmtDate(_dateEnd!)}';
    } else {
      label = '日期不限';
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openDateFilter,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: textBody),
          Icon(Icons.arrow_drop_down, color: colorTextPrimary),
        ],
      ),
    );
  }

  Future<void> _openDateFilter() async {
    final result = await showDialog<(DateTime?, DateTime?)>(
      context: context,
      builder: (context) =>
          DateFilterSheet(initialStart: _dateStart, initialEnd: _dateEnd),
    );
    if (result == null) return; // 取消，保持原筛选
    setState(() {
      _dateStart = result.$1;
      _dateEnd = result.$2;
      _datePreset = _matchPreset(result.$1, result.$2);
      _applyFilter();
    });
  }

  String _fmtDate(DateTime d) => formatDateYmd(d);

  /// 匹配当前起止日期命中的快捷范围名，未命中返回 null。
  String? _matchPreset(DateTime? start, DateTime? end) {
    if (start == null || end == null) return null;
    return matchPresetName(start, end);
  }

  /// 收支三态轮换：点开下拉只显示除当前外的另外两个选项。
  Widget _buildFlowFilter(Color color) {
    return PopupMenuButton<int>(
      tooltip: '',
      offset: const Offset(0, 36),
      menuPadding: EdgeInsets.zero,
      itemBuilder: (context) => [
        for (var i = 0; i < _flowLabels.length; i++)
          if (i != _flowFilter)
            PopupMenuItem<int>(
              height: 32,
              padding: EdgeInsets.zero,
              value: i,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: spacingM),
                child: Text(_flowLabels[i]),
              ),
            ),
      ],
      onSelected: (v) => setState(() {
        _flowFilter = v;
        _applyFilter();
      }),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _flowLabels[_flowFilter],
            style: textBody.copyWith(color: color),
          ),
          Icon(Icons.arrow_drop_down, color: color),
        ],
      ),
    );
  }
}
