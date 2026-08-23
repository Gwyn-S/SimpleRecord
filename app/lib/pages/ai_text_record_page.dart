import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../services/theme_service.dart';
import '../services/settings.dart';
import '../services/record_service.dart';
import '../models/category.dart';
import '../models/record.dart';
import '../utils/id.dart';
import '../utils/toast.dart';
import '../widgets/ai_record_result_card.dart';
import 'ai_manage_page.dart';
import 'package:dio/dio.dart';

class AiTextBookkeepingPage extends StatefulWidget {
  const AiTextBookkeepingPage({super.key});

  @override
  State<AiTextBookkeepingPage> createState() => _AiTextBookkeepingPageState();
}

class _AiTextBookkeepingPageState extends State<AiTextBookkeepingPage> {
  final _textController = TextEditingController();
  bool _loading = false;
  String? _error;
  AiBookkeepingResult? _result;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      safeShowToast(context, '请输入记账内容');
      return;
    }

    final configs = await loadAiConfigs();
    if (!mounted) return;
    if (configs.isEmpty) {
      safeShowToast(context, '请先配置AI');
      return;
    }

    final textConfigIndex = await Settings.getInt('ai_text_config_index');
    final configIndex = textConfigIndex ?? 0;
    if (configIndex >= configs.length) {
      safeShowToast(context, '请先配置AI');
      return;
    }

    final config = configs[configIndex];
    if (config.url.isEmpty || config.key.isEmpty || config.textModel.isEmpty) {
      safeShowToast(context, '请完善AI配置');
      return;
    }

    final prompt = await Settings.getString('ai_prompt') ?? '';

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 60);
      final url = config.url.endsWith('/')
          ? config.url.substring(0, config.url.length - 1)
          : config.url;

      final apiUrl = '$url/chat/completions';

      final systemPrompt = prompt.isEmpty
          ? '你是一个记账助手。用户会输入消费或收入的描述，你需要解析出：isExpense(是否支出，true/false)、categoryName(分类名称)、amountCents(金额，单位分)、remark(备注)、date(日期，格式yyyy-MM-dd，今天则返回空字符串)。只返回JSON，不要其他内容。可用分类：${expenseCategories.map((c) => c.name).join("、")}、${incomeCategories.map((c) => c.name).join("、")}。'
          : prompt;

      Response? lastResponse;
      for (int retry = 0; retry < 3; retry++) {
        try {
          lastResponse = await dio.post(
            apiUrl,
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
          if (e.response?.statusCode == 429 && retry < 2) {
            await Future.delayed(Duration(seconds: (retry + 1) * 2));
            continue;
          }
          rethrow;
        }
      }

      if (!mounted) return;

      final response = lastResponse!;

      final content = response.data['choices'][0]['message']['content'] as String;
      final jsonStr = content.replaceAll('```json', '').replaceAll('```', '').trim();
      final parsed = Map<String, dynamic>.from(
        _parseJson(jsonStr),
      );

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

      setState(() {
        _result = AiBookkeepingResult(
          isExpense: isExpense,
          categoryName: categoryName,
          amountCents: amountCents,
          remark: remark,
          date: date,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'API请求失败：$e';
        _loading = false;
      });
    }
  }

  dynamic _parseJson(String text) {
    try {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final jsonStr = text.substring(start, end + 1);
        return _decodeJson(jsonStr);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  dynamic _decodeJson(String jsonStr) {
    jsonStr = jsonStr.replaceAll("'", '"');
    final map = <String, dynamic>{};
    final regex = RegExp(r'"(\w+)"\s*:\s*("[^"]*"|\d+\.?\d*|true|false|null)');
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
        map[key] = value.substring(1, value.length - 1);
      } else {
        map[key] = double.tryParse(value) ?? value;
      }
    }
    return map;
  }

  Future<void> _saveRecord() async {
    if (_result == null) return;

    final record = Record(
      id: genId(),
      ledgerId: currentLedgerId.value,
      isExpense: _result!.isExpense,
      categoryName: _result!.categoryName,
      amountCents: _result!.amountCents,
      remark: _result!.remark,
      date: _result!.date,
      createdAt: DateTime.now(),
    );

    await insertRecord(record);
    if (!mounted) return;
    safeShowToast(context, '记账成功');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('文字记账'),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: colorBackgroundPage,
      body: Padding(
        padding: const EdgeInsets.all(spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(spacingL),
              child: TextField(
                controller: _textController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '例如：午餐35元、打车20元、工资8000',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: spacingM),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: _loading ? null : _analyze,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('识别'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: spacingM),
              Text(_error!, style: const TextStyle(color: colorDelete)),
            ],
            if (_result != null) ...[
              const SizedBox(height: spacingL),
              AiBookkeepingResultCard(result: _result!),
              const SizedBox(height: spacingM),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _saveRecord,
                  child: const Text('确认记账'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
