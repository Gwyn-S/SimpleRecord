import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/record.dart';
import '../services/export_service.dart';
import '../services/record_service.dart';
import '../services/theme_service.dart';
import '../utils/calendar_utils.dart';
import '../utils/formatters.dart';
import '../utils/toast.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _flowLabels = ['收支', '收入', '支出'];

  final _searchController = TextEditingController();
  List<Record> _allRecords = [];
  List<Record> _filtered = [];
  int _flowFilter = 0; // 0=不限 1=收入 2=支出
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    recordsVersion.addListener(_load);
    currentLedgerId.addListener(_load);
  }

  @override
  void dispose() {
    _searchController.dispose();
    recordsVersion.removeListener(_load);
    currentLedgerId.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final records = await loadRecords(ledgerId: currentLedgerId.value);
    if (!mounted) return;
    setState(() {
      _allRecords = records;
      _filtered = _filterRecords();
    });
  }

  List<Record> _filterRecords() {
    final q = _searchController.text.trim().toLowerCase();
    return _allRecords.where((r) {
      if (_flowFilter == 1 && r.isExpense) return false;
      if (_flowFilter == 2 && !r.isExpense) return false;
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
                    const Icon(Icons.search, size: 20, color: colorTextSecondary),
                    const SizedBox(width: spacingXS),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        style: textBody,
                        decoration: const InputDecoration(
                          hintText: '输入分类，备注，标签',
                          hintStyle: textHint,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (_) => setState(() => _filtered = _filterRecords()),
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
            padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingS),
            child: Row(
              children: [
                _buildStaticFilter('账户不限', themeColor),
                const SizedBox(width: spacingL),
                _buildStaticFilter('日期不限', themeColor),
                const SizedBox(width: spacingL),
                _buildStaticFilter('金额不限', themeColor),
                const Spacer(),
                OutlinedButton(
                  onPressed: _busy ? null : _exportCsv,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFF6F6F6),
                    foregroundColor: colorTextPrimary,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(radiusTiny),
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
            color: const Color(0xFFFAFAFA),
            padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingS),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('记录数 ${_filtered.length}', style: textItemSub),
                const SizedBox(width: spacingM),
                Text('收入：${formatAmount(income)}', style: textItemSub),
                const SizedBox(width: spacingM),
                Text('支出：${formatAmount(expense)}', style: textItemSub),
                const SizedBox(width: spacingM),
                Text('结余：${formatAmount(income - expense)}', style: textItemSub),
              ],
            ),
          ),
          const SizedBox(height: spacingXL),
          Center(
            child: Text(
              _filtered.isEmpty && _searchController.text.trim().isEmpty
                  ? '输入关键词搜索，或下拉筛选收支'
                  : '暂无结果',
              style: textHint,
            ),
          ),
        ],
      ),
    );
  }

  /// 静态下拉（暂不实现筛选效果）。
  Widget _buildStaticFilter(String label, Color themeColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: textBody),
        Icon(Icons.arrow_drop_down, color: colorTextPrimary),
      ],
    );
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
        _filtered = _filterRecords();
      }),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_flowLabels[_flowFilter], style: textBody.copyWith(color: color)),
          Icon(Icons.arrow_drop_down, color: color),
        ],
      ),
    );
  }
}
