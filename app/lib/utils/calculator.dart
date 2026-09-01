String evaluate(String expr) {
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

bool endsWithOp(String s) => s.endsWith('+') || s.endsWith('-') || s.endsWith('×') || s.endsWith('÷');

/// 金额输入实时预览：以运算符结尾则原样显示，含运算则附结果，否则原样。
String amountPreview(String expr) {
  if (endsWithOp(expr)) return expr;
  if (expr.contains(RegExp(r'[+\-×÷]'))) return '$expr=${evaluate(expr)}';
  return expr;
}
