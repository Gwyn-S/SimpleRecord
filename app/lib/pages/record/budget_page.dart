import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/category.dart';
import '../../services/data/record_service.dart';
import '../../services/core/settings.dart';
import '../../services/core/theme_service.dart';
import '../../utils/formatters.dart';
import '../../utils/toast.dart';

final ValueNotifier<int> budgetVersion = ValueNotifier(0);

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  bool _loading = true;
  int _loadSeq = 0;
  int _monthExpense = 0;
  int _monthBudget = 0;
  final Map<String, int> _categoryExpense = {};
  final Map<String, int> _categoryBudget = {};

  @override
  void initState() {
    super.initState();
    _load();
    recordsVersion.addListener(_load);
    currentLedgerId.addListener(_load);
    currentMonth.addListener(_load);
  }

  @override
  void dispose() {
    recordsVersion.removeListener(_load);
    currentLedgerId.removeListener(_load);
    currentMonth.removeListener(_load);
    super.dispose();
  }

  String get _monthKey {
    final m = currentMonth.value;
    return '${m.year}-${m.month}';
  }

  String get _budgetPrefix => 'budget_${currentLedgerId.value ?? 'none'}';

  String get _monthBudgetKey => '${_budgetPrefix}_month_$_monthKey';

  String _catBudgetKey(String name) =>
      '${_budgetPrefix}_cat_${_monthKey}_$name';

  int get _daysInMonth =>
      DateTime(currentMonth.value.year, currentMonth.value.month + 1, 0).day;

  int get _elapsedDays {
    final now = DateTime.now();
    final m = currentMonth.value;
    if (now.year == m.year && now.month == m.month) {
      return now.day.clamp(1, _daysInMonth);
    }
    return _daysInMonth;
  }

  int get _remainingDays {
    final now = DateTime.now();
    final m = currentMonth.value;
    if (now.year == m.year && now.month == m.month) {
      return _daysInMonth - now.day;
    }
    return 0;
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final records = await loadRecords(
      ledgerId: currentLedgerId.value,
      month: currentMonth.value,
    );
    final catExp = <String, int>{};
    for (final r in records) {
      if (r.isExpense) {
        catExp[r.categoryName] = (catExp[r.categoryName] ?? 0) + r.amountCents;
      }
    }
    final monthBudget = await Settings.getInt(_monthBudgetKey) ?? 0;
    final catBudget = <String, int>{};
    for (final c in expenseCategories) {
      catBudget[c.name] = await Settings.getInt(_catBudgetKey(c.name)) ?? 0;
    }
    if (seq != _loadSeq || !mounted) return;
    setState(() {
      _monthExpense = records
          .where((r) => r.isExpense)
          .fold(0, (s, r) => s + r.amountCents);
      _monthBudget = monthBudget;
      _categoryExpense
        ..clear()
        ..addAll(catExp);
      _categoryBudget
        ..clear()
        ..addAll(catBudget);
      _loading = false;
    });
  }

  Future<void> _editBudget({
    required String title,
    required int current,
    required ValueChanged<int> onSave,
  }) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: textDialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(context, controller.text);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (text == null || !mounted) return;
    final s = text.trim();
    if (s.isEmpty) {
      onSave(0);
      return;
    }
    final v = double.tryParse(s);
    if (v == null || !v.isFinite || v < 0) {
      showToast(context, '金额格式不正确');
      return;
    }
    onSave((v * 100).round());
  }

  Future<void> _saveMonthBudget(int cents) async {
    await Settings.setInt(_monthBudgetKey, cents);
    if (!mounted) return;
    budgetVersion.value++;
    setState(() => _monthBudget = cents);
  }

  Future<void> _saveCatBudget(String name, int cents) async {
    await Settings.setInt(_catBudgetKey(name), cents);
    if (!mounted) return;
    final newCatBudget = <String, int>{..._categoryBudget};
    newCatBudget[name] = cents;
    var newMonthBudget = _monthBudget;
    if (newMonthBudget == 0) {
      newMonthBudget = newCatBudget.values.fold(0, (s, v) => s + v);
      if (newMonthBudget > 0) {
        await Settings.setInt(_monthBudgetKey, newMonthBudget);
        if (!mounted) return;
      }
    }
    budgetVersion.value++;
    setState(() {
      _categoryBudget[name] = cents;
      _monthBudget = newMonthBudget;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorBackgroundPage,
      appBar: AppBar(
        title: const Text('预算中心', style: textTitle),
        backgroundColor: Theme.of(context).extension<AppThemeColors>()!.primary,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildMonthCard(),
                _buildCategoryHeader(),
                Expanded(child: _buildCategoryCard()),
              ],
            ),
    );
  }

  Widget _buildMonthCard() {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    final budget = _monthBudget;
    final remaining = budget - _monthExpense;
    final hasBudget = budget > 0;
    final ratio = hasBudget ? (_monthExpense / budget).clamp(0.0, 1.0) : 0.0;
    final avg = _elapsedDays > 0 ? _monthExpense / _elapsedDays : 0;
    final perDay = _remainingDays > 0 && hasBudget
        ? remaining / _remainingDays
        : 0.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(spacingM, 8, spacingM, 0),
      padding: const EdgeInsets.all(spacingL),
      decoration: BoxDecoration(
        color: colorBackgroundCard,
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RingProgress(
                size: 96,
                progress: ratio,
                color: remaining < 0 ? colorExpense : themeColor,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasBudget
                          ? '${(_monthExpense / budget * 100).toStringAsFixed(0)}%'
                          : '0%',
                      style: TextStyle(
                        fontSize: hasBudget ? 16 : 12,
                        color: colorTextPrimary,
                      ),
                    ),
                    if (hasBudget) ...[
                      const SizedBox(height: 2),
                      Text(
                        '已用',
                        style: textItemSub.copyWith(color: colorTextPrimary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: spacingL),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '剩余月预算',
                      style: textSecondary.copyWith(color: colorTextPrimary),
                    ),
                    const SizedBox(height: spacingXS),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hasBudget ? formatAmount(remaining) : '0.00',
                        style: textBudgetRemaining,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: spacingM),
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorDivider,
          ),
          Padding(
            padding: const EdgeInsets.only(top: spacingM),
            child: Row(
              children: [
                Expanded(
                  child: _statItem(
                    label: '该月预算',
                    value: hasBudget ? formatAmount(budget) : '0.00',
                    onEdit: () => _editBudget(
                      title: '设置月预算',
                      current: budget,
                      onSave: _saveMonthBudget,
                    ),
                  ),
                ),
                Expanded(
                  child: _statItem(
                    label: '日均消费',
                    value: formatAmount(avg.round()),
                  ),
                ),
                Expanded(
                  child: _statItem(
                    label: '剩余日预算',
                    value: _remainingDays > 0 && hasBudget
                        ? formatAmount(perDay.round())
                        : '0.00',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem({
    required String label,
    required String value,
    VoidCallback? onEdit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: textItemSub.copyWith(color: colorTextPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: spacingXS),
              GestureDetector(
                onTap: onEdit,
                child: const Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: colorTextSecondary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: spacingXS),
        GestureDetector(
          onTap: onEdit,
          behavior: HitTestBehavior.opaque,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 18, color: colorTextPrimary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        spacingM,
        spacingXL,
        spacingM,
        spacingXS,
      ),
      child: Row(
        children: [
          const Text(
            '分类预算',
            style: TextStyle(fontSize: 17, color: colorTextPrimary),
          ),
          const Spacer(),
          Text('本月支出', style: textItemSub),
          const SizedBox(width: spacingXS),
          Text(formatAmount(_monthExpense), style: textAmountSummary),
        ],
      ),
    );
  }

  Widget _buildCategoryCard() {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(spacingM, 0, spacingM, spacingS),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorBackgroundCard,
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      child: ListView.separated(
        itemCount: expenseCategories.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          thickness: borderWidthThin,
          color: colorDivider,
        ),
        itemBuilder: (_, i) => _categoryItem(expenseCategories[i], themeColor),
      ),
    );
  }

  Widget _categoryItem(Category c, Color themeColor) {
    final spent = _categoryExpense[c.name] ?? 0;
    final budget = _categoryBudget[c.name] ?? 0;
    final ratio = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0);
    final over = budget > 0 && spent > budget;
    return GestureDetector(
      onTap: () => _editBudget(
        title: '${c.name}预算',
        current: budget,
        onSave: (v) => _saveCatBudget(c.name, v),
      ),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: 10),
        child: Row(
          children: [
            Container(
              width: sizeCategoryCircle,
              height: sizeCategoryCircle,
              decoration: const BoxDecoration(
                color: colorIconLightBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(c.icon, size: iconSizeXLarge, color: colorIconGray),
            ),
            const SizedBox(width: spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(c.name, style: textBody),
                      const Spacer(),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '支出',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorTextHint,
                              ),
                            ),
                            TextSpan(
                              text: ' ${formatAmount(spent)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: colorTextPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: spacingS),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: colorDivider,
                      valueColor: AlwaysStoppedAnimation(
                        over ? colorExpense : themeColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    budget > 0 ? '支出预算 ${formatAmount(budget)}' : '支出预算 未设置',
                    style: textItemSub.copyWith(color: colorTextHint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingProgress extends StatelessWidget {
  final double size;
  final double progress;
  final Color color;
  final Widget center;

  const _RingProgress({
    required this.size,
    required this.progress,
    required this.color,
    required this.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(progress: progress, color: color),
          ),
          center,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.08;
    final inset = stroke / 2;
    final arc = (Offset.zero & size).deflate(inset);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = colorDivider;
    canvas.drawArc(arc, 0, 2 * math.pi, false, bg);
    if (progress > 0) {
      final fg = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(arc, -math.pi / 2, 2 * math.pi * progress, false, fg);
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
