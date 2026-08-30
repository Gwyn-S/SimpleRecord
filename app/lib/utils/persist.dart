/// 配置输入即存：值变更时调用 [onCommit]，未变更跳过；返回最新值供缓存。
String persistIfChanged(
    String value, String? last, void Function(String) onCommit) {
  if (value == last) return last!;
  onCommit(value);
  return value;
}