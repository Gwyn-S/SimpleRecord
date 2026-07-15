import 'package:flutter/material.dart';
import '../theme.dart';
import '../icon/app_icons.dart';
import '../models/record.dart';

class ManualEntryPage extends StatefulWidget {
  const ManualEntryPage({super.key});

  @override
  State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  bool _isExpense = true;
  int? _selectedCategory;
  String _amount = '0';
  DateTime _selectedDate = DateTime.now();
  final _remarkController = TextEditingController();

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  String _evaluate(String expr) {
    expr = expr.replaceAll('×', '*').replaceAll('÷', '/');
    try {
      final nums = <double>[];
      final parts = expr.split(RegExp(r'([+\-*/])'));
      for (final p in parts) {
        if (p.isEmpty) continue;
        nums.add(double.parse(p));
      }
      final operators = RegExp(r'[+\-*/]').allMatches(expr).map((m) => m.group(0)!).toList();
      int i = 0;
      while (i < operators.length) {
        if (operators[i] == '*' || operators[i] == '/') {
          final a = nums[i];
          final b = nums[i + 1];
          nums[i] = operators[i] == '*' ? a * b : (b == 0 ? 0 : a / b);
          nums.removeAt(i + 1);
          operators.removeAt(i);
        } else {
          i++;
        }
      }
      double result = nums.first;
      for (int j = 0; j < operators.length; j++) {
        result = operators[j] == '+' ? result + nums[j + 1] : result - nums[j + 1];
      }
      if (result == result.roundToDouble() && !expr.contains('.')) {
        return result.toInt().toString();
      }
      return result.toStringAsFixed(2);
    } catch (_) {
      return expr;
    }
  }

  bool _endsWithOp(String s) => s.endsWith('+') || s.endsWith('-') || s.endsWith('×') || s.endsWith('÷');

  String _getCategoryName() {
    final cats = _isExpense ? expenseCategories : incomeCategories;
    if (_selectedCategory == null || _selectedCategory! >= cats.length) return '其他';
    return cats[_selectedCategory!].name;
  }

  Future<void> _saveRecord() async {
    final result = _evaluate(_amount);
    final amount = double.tryParse(result) ?? 0;
    if (amount == 0) return;
    final record = Record(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bookId: currentBookId.value,
      isExpense: _isExpense,
      categoryName: _getCategoryName(),
      amount: amount,
      remark: _remarkController.text,
      date: _selectedDate,
      createdAt: DateTime.now(),
    );
    final records = await loadRecords();
    records.insert(0, record);
    await saveRecords(records);
  }

  void _onKeyPressed(String key) {
    if (key == '再记') {
      _saveRecord().then((_) {
        setState(() {
          _amount = '0';
          _remarkController.clear();
          _selectedCategory = null;
        });
      });
      return;
    }
    if (key == '完成') {
      _saveRecord().then((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    setState(() {
      if (key == 'C') {
        _amount = '0';
      } else if (key == '⌫') {
        if (_amount.length > 1) {
          _amount = _amount.substring(0, _amount.length - 1);
        } else {
          _amount = '0';
        }
      } else if (key == '.') {
        final segment = _amount.split(RegExp(r'[+\-×÷]')).last;
        if (!segment.contains('.')) _amount += '.';
      } else if (key == '00') {
        final segment = _amount.split(RegExp(r'[+\-×÷]')).last;
        if (segment.contains('.')) {
          final decimals = segment.split('.')[1];
          if (decimals.isEmpty) {
            _amount += '00';
          } else if (decimals.length == 1) {
            _amount += '0';
          }
        } else if (segment != '0' && segment != '00') {
          _amount += '00';
        }
      } else if ('+-×÷'.contains(key)) {
        if (_endsWithOp(_amount)) {
          _amount = _amount.substring(0, _amount.length - 1) + key;
        } else if (_amount != '0') {
          _amount += key;
        }
      } else {
        if (_amount == '0') {
          _amount = key;
        } else {
          final segment = _amount.split(RegExp(r'[+\-×÷]')).last;
          if (segment.contains('.') && segment.split('.')[1].length >= 2) return;
          _amount += key;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) => AppBar(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '',
              onPressed: () => Navigator.pop(context),
            ),
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: SizedBox(
                width: 144,
                height: 4,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      left: _isExpense ? 0.0 : 72.0,
                      top: 0,
                      child: Container(
                        width: 72,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _isExpense = true),
                  child: SizedBox(
                    width: 72,
                    height: 36,
                    child: Center(
                      child: Text(
                        '支出',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: _isExpense ? FontWeight.w600 : FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _isExpense = false),
                  child: SizedBox(
                    width: 72,
                    height: 36,
                    child: Center(
                      child: Text(
                        '收入',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: !_isExpense ? FontWeight.w600 : FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<Color>(
              valueListenable: themeColorNotifier,
              builder: (context, color, _) {
                final categories = _isExpense ? expenseCategories : incomeCategories;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      final selected = _selectedCategory == index;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = index),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: selected ? color.withValues(alpha: 0.15) : const Color(0xFFF5F5F5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                cat.icon,
                                size: 24,
                                color: selected ? color : const Color(0xFF333333),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              cat.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: selected ? color : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<Color>(
                  valueListenable: themeColorNotifier,
                  builder: (context, color, _) => SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _remarkController,
                      maxLength: 20,
                      style: const TextStyle(fontSize: 14, color: Colors.black),
                      cursorColor: color,
                      decoration: InputDecoration(
                        hintText: '备注',
                        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF999999)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                      ),
                    ),
                  ),
                ),
                Text(
                  _endsWithOp(_amount)
                      ? '¥ $_amount'
                      : _amount.contains(RegExp(r'[+\-×÷]'))
                          ? '¥ $_amount = ${_evaluate(_amount)}'
                          : '¥ $_amount',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.black),
                ),
              ],
            ),
          ),
          _buildOptionBar(),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE0E0E0)),
          _buildKeyboard(),
        ],
      ),
    );
  }

  String _formatSelectedDate() {
    return '${_selectedDate.month}月${_selectedDate.day}日';
  }

  Widget _buildOptionBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildOptionItem(
            icon: Icons.calendar_today_outlined,
            label: _formatSelectedDate(),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
          ),
          const SizedBox(width: 24),
          // TODO: 接入账户选择功能（关联 asset_accounts）
          _buildOptionItem(
            icon: Icons.account_balance_wallet_outlined,
            label: '账户',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('账户选择功能开发中'), duration: Duration(seconds: 1)),
            ),
          ),
          const SizedBox(width: 24),
          // TODO: 接入标签功能（关联 tags 表）
          _buildOptionItem(
            icon: Icons.label_outline,
            label: '标签',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('标签功能开发中'), duration: Duration(seconds: 1)),
            ),
          ),
          const SizedBox(width: 24),
          // TODO: 接入图片附件功能
          _buildOptionItem(
            icon: Icons.camera_alt_outlined,
            label: '图片',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('图片附件功能开发中'), duration: Duration(seconds: 1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF999999)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF999999))),
        ],
      ),
    );
  }

  Widget _buildKeyboard() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildKeyboardRow(['7', '8', '9', 'C', '⌫']),
          _buildDivider(),
          _buildKeyboardRow(['4', '5', '6', '+', '-']),
          _buildDivider(),
          _buildKeyboardRow(['1', '2', '3', '×', '÷']),
          _buildDivider(),
          _buildKeyboardRow(['.', '0', '00', '再记', '完成']),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const SizedBox(
      height: 1,
      child: Divider(height: 1, thickness: 0.5, color: Color(0xFFE0E0E0)),
    );
  }

  Widget _buildKeyboardRow(List<String> keys) {
    return Row(
      children: keys.map((key) {
        return Expanded(
          child: GestureDetector(
            onTap: () => _onKeyPressed(key),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: const Color(0xFFE0E0E0), width: 0.5),
                ),
              ),
              alignment: Alignment.center,
              child: _buildKeyChild(key),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeyChild(String key) {
    if (key == '再记') {
      return const Text(
        '再记',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black),
      );
    }
    if (key == '完成') {
      return ValueListenableBuilder<Color>(
        valueListenable: themeColorNotifier,
        builder: (context, color, _) => Container(
          alignment: Alignment.center,
          color: color,
          child: const Text(
            '完成',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white),
          ),
        ),
      );
    }
    return Text(
      key,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: key == 'C' ? const Color(0xFFE53935) : Colors.black,
      ),
    );
  }
}
