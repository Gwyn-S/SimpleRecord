import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../utils/calculator.dart';

/// 计算器键盘（数字/运算符/退格/清零 + 自定义末行键与完成键）。
/// 金额表达式由父级持有，按键产生的变更通过 [onChanged] 回传。
class CalcKeyboard extends StatelessWidget {
  final String amount;
  final ValueChanged<String> onChanged;

  /// 末行第三键的文字（如 '再记' / '返回'）。
  final String extraLabel;
  final VoidCallback onExtra;
  final VoidCallback onDone;

  const CalcKeyboard({
    super.key,
    required this.amount,
    required this.onChanged,
    required this.extraLabel,
    required this.onExtra,
    required this.onDone,
  });

  void _handleKey(String key) {
    if (key == 'C') {
      onChanged('0');
      return;
    }
    if (key == '⌫') {
      onChanged(
        amount.length > 1 ? amount.substring(0, amount.length - 1) : '0',
      );
      return;
    }
    var next = amount;
    if (key == '.') {
      final segment = next.split(RegExp(r'[+\-×÷]')).last;
      if (!segment.contains('.')) next += '.';
    } else if (key == '00') {
      final segment = next.split(RegExp(r'[+\-×÷]')).last;
      if (segment.contains('.')) {
        final decimals = segment.split('.')[1];
        if (decimals.isEmpty) {
          next += '00';
        } else if (decimals.length == 1) {
          next += '0';
        }
      } else if (segment != '0' && segment != '00') {
        next += '00';
      }
    } else if ('+-×÷'.contains(key)) {
      if (endsWithOp(next)) {
        next = next.substring(0, next.length - 1) + key;
      } else if (next != '0') {
        next += key;
      }
    } else {
      if (next == '0') {
        next = key;
      } else {
        final segment = next.split(RegExp(r'[+\-×÷]')).last;
        if (segment.contains('.') && segment.split('.')[1].length >= 2) return;
        next += key;
      }
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colorBackgroundCard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildKeyboardRow(['7', '8', '9'], _buildBackspace()),
          _buildDivider(),
          _buildKeyboardRow(['4', '5', '6'], _buildOpsPair('+', '-')),
          _buildDivider(),
          _buildKeyboardRow(['1', '2', '3'], _buildOpsPair('×', '÷')),
          _buildDivider(),
          _buildKeyboardRow(['.', '0', extraLabel], _buildDone(context)),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const SizedBox(
      height: 1,
      child: Divider(
        height: 1,
        thickness: borderWidthThin,
        color: colorBorderKeyboard,
      ),
    );
  }

  Widget _buildKeyboardRow(List<String> keys, Widget trailing) {
    return Row(
      children: [
        ...keys.map((key) => Expanded(child: _buildKey(key))),
        Expanded(child: trailing),
      ],
    );
  }

  Widget _buildKey(String key) {
    return GestureDetector(
      onTap: () {
        if (key == extraLabel) {
          onExtra();
        } else {
          _handleKey(key);
        }
      },
      child: Container(
        height: heightKeyboardRow,
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(
              color: colorBorderKeyboard,
              width: borderWidthThin,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          key,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: colorTextPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildBackspace() {
    return GestureDetector(
      onTap: () => _handleKey('⌫'),
      child: Container(
        height: heightKeyboardRow,
        alignment: Alignment.center,
        child: const Text(
          '⌫',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: colorTextPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildOpsPair(String a, String b) {
    return Row(
      children: [
        Expanded(child: _buildKey(a)),
        Expanded(child: _buildKey(b)),
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    return GestureDetector(
      onTap: onDone,
      child: Container(
        height: heightKeyboardRow,
        color: Theme.of(context).extension<AppThemeColors>()!.primary,
        alignment: Alignment.center,
        child: const Text('完成', style: textButtonPrimary),
      ),
    );
  }
}
