import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../models/ai_config.dart';
import '../models/ai_record_result.dart';
import '../models/asset_account.dart';
import '../models/category.dart';
import '../models/record.dart';
import '../services/record_service.dart';
import '../services/settings.dart';
import '../services/transfer_service.dart';
import '../utils/formatters.dart';
import '../utils/id.dart';
import '../utils/log.dart';

const aiRecordKey = 'ai_bookkeeping_enabled';
const _aiConfigsKey = 'ai_configs';
const _aiPromptKey = 'ai_prompt';
const _maxRetries = 3;
const _retryDelay = 2;
final _dio = Dio();
final defaultAiPrompt = '''你是一个记账助手。解析用户的消费/收入/转账描述，返回 JSON 数组。

当前时间：{{CURRENT_TIME}}

{{CATEGORIES}}

{{ACCOUNTS}}

## 输出格式
始终返回 JSON 数组，即使只有一笔也用 [...] 包裹。

## 字段规则

### type（必填）
- "expense"：支出
- "income"：收入
- "transfer"：转账

### amount（必填）
- 金额，单位分（元×100），必须是整数
- 例：35元 → 3500

### categoryName（必填）
- 从上方可用分类中选择最匹配的
- 无法匹配时返回"其他"

### accountId（可选）
- 从上方可用账户中匹配支付/收款账户，返回账户名（如：微信）
- 不要返回账户id，只返回账户名
- 匹配不到则返回空字符串，由用户手动选择

### fromAccountId / toAccountId（转账必填）
- 转出账户名 / 转入账户名（如：建行、微信）
- 不要返回账户id，只返回账户名
- 匹配不到则返回空字符串

### remark（可选）
- ≤15字
- 优先级：商家名 > 商品名 > 用户描述
- 例："星巴克"、"打车去公司"、"给女儿买"
- 无明确内容则留空

### date（必填）
- 绝对日期 yyyy-MM-dd
- 必须将相对日期转换为具体日期
- 未提及时间则使用当前日期

## 示例

### 单笔支出
"昨天午餐微信35"
[{"type":"expense","amount":3500,"categoryName":"餐饮","accountId":"微信","remark":"午餐","date":"2026-08-26"}]

### 单笔收入
"收到工资8000"
[{"type":"income","amount":800000,"categoryName":"工资","remark":"","date":"2026-08-27"}]

### 转账
"从建行转800到微信"
[{"type":"transfer","fromAccountId":"建行","toAccountId":"微信","amount":80000,"remark":"","date":"2026-08-27"}]

### 多笔
"早上地铁5元，中午吃饭40元，晚上买水果35"
[{"type":"expense","amount":500,"categoryName":"交通","remark":"地铁","date":"2026-08-27"},{"type":"expense","amount":4000,"categoryName":"餐饮","remark":"午餐","date":"2026-08-27"},{"type":"expense","amount":3500,"categoryName":"购物","remark":"水果","date":"2026-08-27"}]

## 注意
- 只返回 JSON 数组，不要其他内容
- 金额必须是整数分，不要返回小数
- 不确定分类时返回"其他"
- 不确定日期时返回当前日期
- 无法匹配账户时留空，由用户手动选择
''';

/// 加载 AI 配置列表
Future<List<AiConfig>> loadAiConfigs() async {
  final json = await Settings.getString(_aiConfigsKey);
  if (json == null || json.isEmpty) return [];
  try {
    final list = jsonDecode(json) as List;
    return list
        .map((e) => AiConfig.fromMap(e as Map<String, dynamic>))
        .toList();
  } catch (e) {
    appLog('[ai] loadAiConfigs parse failed: $e');
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

/// 构建完整提示词（替换模板变量）
String buildAiPrompt({
  required String template,
  required List<AssetAccount> accounts,
}) {
  final now = DateTime.now();
  final currentTime =
      '${now.year}-${pad2(now.month)}-${pad2(now.day)} ${pad2(now.hour)}:${pad2(now.minute)}:${pad2(now.second)}';

  final categories =
      '''
## 可用分类
支出：${expenseCategories.map((c) => c.name).join('、')}
收入：${incomeCategories.map((c) => c.name).join('、')}
''';

  final accountsText = accounts.isEmpty
      ? ''
      : '''
## 可用账户
${accounts.map((a) => '- ${a.displayName}(id:${a.id})').join('\n')}
''';

  return template
      .replaceAll('{{CURRENT_TIME}}', currentTime)
      .replaceAll('{{CATEGORIES}}', categories)
      .replaceAll('{{ACCOUNTS}}', accountsText);
}

/// 解析 AI 返回的 JSON 文本（支持单对象和数组）
List<Map<String, dynamic>> parseAiJsonList(String text) {
  // 先尝试解析数组
  try {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start >= 0 && end > start) {
      final jsonStr = text.substring(start, end + 1);
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
  } catch (e) {
    appLog('[ai] parseAiJsonList failed: $e');
  }

  // 降级：尝试解析单个对象
  final single = parseAiJson(text);
  if (single.isNotEmpty) return [single];

  return [];
}

/// 解析 AI 返回的 JSON 文本（单对象）
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
  } catch (e) {
    appLog('[ai] parseAiJson failed: $e');
  }

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
  final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  final response = await _dio.get(
    '$baseUrl/models',
    options: Options(
      headers: {'Authorization': 'Bearer $key'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  if (response.statusCode != 200) {
    throw Exception('测试失败：${response.statusCode}');
  }
}

/// 调用 AI API 进行文字记账识别（返回多条结果）
Future<List<AiRecordResult>> analyzeTextList({
  required AiConfig config,
  required String text,
  String? customPrompt,
  List<AssetAccount> accounts = const [],
  required String model,
}) async {
  final template = (customPrompt?.isNotEmpty == true)
      ? customPrompt!
      : defaultAiPrompt;
  final systemPrompt = buildAiPrompt(template: template, accounts: accounts);

  final content = await _chatCompletion(
    config: config,
    model: model,
    messages: [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': text},
    ],
    receiveTimeout: const Duration(seconds: 60),
  );

  return _parseResults(content, accounts);
}

AiRecordResult _parseOneResult(Map<String, dynamic> parsed) {
  final type = parsed['type'] as String? ?? 'expense';
  final categoryName = parsed['categoryName'] as String? ?? '其他';
  final amountRaw = parsed['amount'];
  final int amountCents;
  if (amountRaw is num) {
    amountCents = amountRaw.toInt();
  } else {
    amountCents = int.tryParse(amountRaw?.toString() ?? '') ?? 0;
  }
  final remark = parsed['remark'] as String? ?? '';
  final accountId = parsed['accountId'] as String? ?? '';
  final fromAccountId = parsed['fromAccountId'] as String? ?? '';
  final toAccountId = parsed['toAccountId'] as String? ?? '';
  final dateStr = parsed['date'] as String?;

  DateTime date = DateTime.now();
  if (dateStr != null && dateStr.isNotEmpty) {
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {
      throw '日期解析失败，请重试';
    }
  }

  return AiRecordResult(
    type: type,
    categoryName: categoryName,
    amountCents: amountCents,
    remark: remark,
    accountId: accountId,
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
    date: date,
  );
}

/// 调用 AI API 进行图片记账识别
Future<List<AiRecordResult>> analyzeImage({
  required AiConfig config,
  required File imageFile,
  String? customPrompt,
  List<AssetAccount> accounts = const [],
}) async {
  final template = (customPrompt?.isNotEmpty == true)
      ? customPrompt!
      : defaultAiPrompt;
  final systemPrompt = buildAiPrompt(template: template, accounts: accounts);

  final bytes = await imageFile.readAsBytes();
  final base64Image = base64Encode(bytes);
  final ext = imageFile.path.split('.').last.toLowerCase();
  final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

  final content = await _chatCompletion(
    config: config,
    model: config.visionModel,
    messages: [
      {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '请识别这张图片中的消费/收入信息，返回记账JSON'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
          },
        ],
      },
    ],
    receiveTimeout: const Duration(seconds: 120),
  );

  return _parseResults(content, accounts);
}

/// 调用 OpenAI 兼容 chat/completions 接口，返回模型输出文本。
Future<String> _chatCompletion({
  required AiConfig config,
  required String model,
  required List<Map<String, dynamic>> messages,
  required Duration receiveTimeout,
}) async {
  final url = config.url.endsWith('/')
      ? config.url.substring(0, config.url.length - 1)
      : config.url;

  Response? lastResponse;
  for (int retry = 0; retry < _maxRetries; retry++) {
    try {
      lastResponse = await _dio.post(
        '$url/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${config.key}',
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: receiveTimeout,
        ),
        data: {'model': model, 'messages': messages, 'temperature': 0},
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
  return content;
}

/// 解析模型输出文本为记账结果
List<AiRecordResult> _parseResults(
  String content,
  List<AssetAccount> accounts,
) {
  final jsonStr = content
      .replaceAll('```json', '')
      .replaceAll('```', '')
      .trim();
  final parsedList = parseAiJsonList(jsonStr);

  if (parsedList.isEmpty) {
    throw Exception('AI 返回内容无法解析');
  }

  return _resolveAccounts(parsedList.map(_parseOneResult).toList(), accounts);
}

/// 将 AI 返回的账户名/账户id解析为真实账户id。
/// 无账户上下文(accounts 为空)时 AI 返回的任何账户名都不可信，
/// 一律置空，避免把编造的字符串当作 account_id 落库产生孤儿记录。
List<AiRecordResult> _resolveAccounts(
  List<AiRecordResult> results,
  List<AssetAccount> accounts,
) {
  final byId = {for (final a in accounts) a.id: a};
  final byName = {
    for (final a in accounts) a.name: a,
    for (final a in accounts) a.displayName: a,
  };
  final byLowerName = {
    for (final a in accounts) a.name.toLowerCase(): a,
    for (final a in accounts) a.displayName.toLowerCase(): a,
  };

  String resolve(String raw) {
    if (raw.isEmpty) return '';
    if (byId.containsKey(raw)) return raw;
    if (byName.containsKey(raw)) return byName[raw]!.id;
    if (byLowerName.containsKey(raw.toLowerCase())) {
      return byLowerName[raw.toLowerCase()]!.id;
    }
    for (final a in accounts) {
      if (raw.contains(a.name) || a.name.contains(raw)) return a.id;
    }
    return '';
  }

  return results
      .map(
        (r) => AiRecordResult(
          type: r.type,
          amountCents: r.amountCents,
          categoryName: r.categoryName,
          accountId: resolve(r.accountId),
          fromAccountId: resolve(r.fromAccountId),
          toAccountId: resolve(r.toAccountId),
          remark: r.remark,
          date: r.date,
        ),
      )
      .toList();
}

/// 保存多条 AI 记账结果。账户缺失时返回提示文案，全部成功返回 null。
Future<String?> saveAiResults(List<AiRecordResult> results) async {
  for (final result in results) {
    if (result.isTransfer) {
      if (result.fromAccountId.isEmpty || result.toAccountId.isEmpty) {
        return '转账账户缺失，请手动记账';
      }
      await insertTransfer(
        fromAccountId: result.fromAccountId,
        toAccountId: result.toAccountId,
        amountCents: result.amountCents,
        remark: result.remark,
        date: result.date,
      );
    } else {
      final record = Record(
        id: genId(),
        ledgerId: currentLedgerId.value,
        accountId: result.accountId.isEmpty ? null : result.accountId,
        isExpense: result.isExpense,
        categoryName: result.categoryName,
        amountCents: result.amountCents,
        remark: result.remark,
        date: result.date,
        createdAt: DateTime.now(),
      );
      await insertRecord(record);
    }
  }
  return null;
}
