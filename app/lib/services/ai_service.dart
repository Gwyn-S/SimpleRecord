import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/ai_record_result.dart';
import '../models/category.dart';
import '../services/settings.dart';

const aiRecordKey = 'ai_bookkeeping_enabled';
const _aiConfigsKey = 'ai_configs';
const _aiPromptKey = 'ai_prompt';
const _maxRetries = 3;
const _retryDelay = 2;
final defaultAiPrompt = '你是一个记账助手。用户会输入消费或收入的描述，你需要解析出：isExpense(是否支出，true/false)、categoryName(分类名称)、amountCents(金额，单位分)、remark(备注)、date(日期，格式yyyy-MM-dd，今天则返回空字符串)。只返回JSON，不要其他内容。可用分类：${expenseCategories.map((c) => c.name).join("、")}、${incomeCategories.map((c) => c.name).join("、")}。';

/// AI 配置模型
class AiConfig {
  String name;
  String url;
  String key;
  String textModel;
  String visionModel;
  String voiceModel;

  AiConfig({
    required this.name,
    required this.url,
    required this.key,
    this.textModel = '',
    this.visionModel = '',
    this.voiceModel = '',
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'url': url,
    'key': key,
    'textModel': textModel,
    'visionModel': visionModel,
    'voiceModel': voiceModel,
  };

  factory AiConfig.fromMap(Map<String, dynamic> m) => AiConfig(
    name: m['name'] as String? ?? '',
    url: m['url'] as String? ?? '',
    key: m['key'] as String? ?? '',
    textModel: m['textModel'] as String? ?? '',
    visionModel: m['visionModel'] as String? ?? '',
    voiceModel: m['voiceModel'] as String? ?? '',
  );
}

/// 加载 AI 配置列表
Future<List<AiConfig>> loadAiConfigs() async {
  final json = await Settings.getString(_aiConfigsKey);
  if (json == null || json.isEmpty) return [];
  try {
    final list = jsonDecode(json) as List;
    return list.map((e) => AiConfig.fromMap(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
}

/// 保存 AI 配置列表
Future<void> saveAiConfigs(List<AiConfig> configs) async {
  final json = jsonEncode(configs.map((c) => c.toMap()).toList());
  await Settings.setString(_aiConfigsKey, json);
}

/// 获取指定类型的配置索引
Future<int?> getConfigIndex(String key) => Settings.getInt(key);

/// 设置指定类型的配置索引
Future<void> setConfigIndex(String key, int? index) async {
  if (index != null) {
    await Settings.setInt(key, index);
  } else {
    await Settings.remove(key);
  }
}

/// 获取自定义提示词
Future<String> getPrompt() async {
  final prompt = await Settings.getString(_aiPromptKey);
  return prompt ?? '';
}

/// 解析 AI 返回的 JSON 文本
Map<String, dynamic> parseAiJson(String text) {
  // 先尝试标准 JSON 解析
  try {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final jsonStr = text.substring(start, end + 1);
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
  } catch (_) {}

  // 降级：手动解析（处理 AI 返回非标准 JSON 的情况）
  try {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final jsonStr = text.substring(start, end + 1);
      return _fallbackParse(jsonStr);
    }
  } catch (_) {}

  return {};
}

Map<String, dynamic> _fallbackParse(String jsonStr) {
  final map = <String, dynamic>{};
  final regex = RegExp(r'"(\w+)"\s*:\s*("([^"]*)"|\d+\.?\d*|true|false|null)');
  for (final match in regex.allMatches(jsonStr)) {
    final key = match.group(1)!;
    final value = match.group(2)!;
    if (value == 'true') {
      map[key] = true;
    } else if (value == 'false') {
      map[key] = false;
    } else if (value == 'null') {
      map[key] = null;
    } else if (value.startsWith('"')) {
      map[key] = match.group(3)!;
    } else {
      map[key] = double.tryParse(value) ?? value;
    }
  }
  return map;
}

/// 测试 AI 配置连通性
Future<void> testAiConnection({
  required String url,
  required String key,
}) async {
  final dio = Dio();
  dio.options.connectTimeout = const Duration(seconds: 10);
  dio.options.receiveTimeout = const Duration(seconds: 10);

  final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  final response = await dio.get(
    '$baseUrl/models',
    options: Options(
      headers: {
        'Authorization': 'Bearer $key',
      },
    ),
  );

  if (response.statusCode != 200) {
    throw Exception('测试失败：${response.statusCode}');
  }
}

/// 调用 AI API 进行文字记账识别
Future<AiRecordResult> analyzeText({
  required AiConfig config,
  required String text,
  String? customPrompt,
}) async {
  final dio = Dio();
  dio.options.connectTimeout = const Duration(seconds: 30);
  dio.options.receiveTimeout = const Duration(seconds: 60);

  final url = config.url.endsWith('/')
      ? config.url.substring(0, config.url.length - 1)
      : config.url;

  final systemPrompt = (customPrompt?.isNotEmpty == true) ? customPrompt! : defaultAiPrompt;

  Response? lastResponse;
  for (int retry = 0; retry < _maxRetries; retry++) {
    try {
      lastResponse = await dio.post(
        '$url/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${config.key}',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': config.textModel,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': text},
          ],
          'temperature': 0,
        },
      );
      break;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429 && retry < _maxRetries - 1) {
        await Future.delayed(Duration(seconds: (retry + 1) * _retryDelay));
        continue;
      }
      rethrow;
    }
  }

  String content;
  try {
    content = lastResponse!.data['choices'][0]['message']['content'] as String;
  } catch (_) {
    throw Exception('AI 返回格式异常');
  }
  final jsonStr = content.replaceAll('```json', '').replaceAll('```', '').trim();
  final parsed = parseAiJson(jsonStr);

  final isExpense = parsed['isExpense'] as bool? ?? true;
  final categoryName = parsed['categoryName'] as String? ?? '其他';
  final amountRaw = parsed['amountCents'];
  final int amountCents;
  if (amountRaw is num) {
    amountCents = amountRaw.toInt();
  } else {
    amountCents = int.tryParse(amountRaw?.toString() ?? '') ?? 0;
  }
  final remark = parsed['remark'] as String? ?? '';
  final dateStr = parsed['date'] as String?;

  DateTime date = DateTime.now();
  if (dateStr != null && dateStr.isNotEmpty) {
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {}
  }

  return AiRecordResult(
    isExpense: isExpense,
    categoryName: categoryName,
    amountCents: amountCents,
    remark: remark,
    date: date,
  );
}
