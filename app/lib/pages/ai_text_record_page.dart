import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../models/ai_record_result.dart';
import '../models/record.dart';
import '../services/ai_service.dart';
import '../services/record_service.dart';
import '../services/theme_service.dart';
import '../utils/id.dart';
import '../utils/toast.dart';
import '../widgets/ai_record_result_card.dart';

class AiTextRecordPage extends StatefulWidget {
  const AiTextRecordPage({super.key});

  @override
  State<AiTextRecordPage> createState() => _AiTextRecordPageState();
}

class _AiTextRecordPageState extends State<AiTextRecordPage> {
  final _textController = TextEditingController();
  bool _loading = false;
  String? _error;
  AiRecordResult? _result;

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

    final configIndex = await getConfigIndex('ai_text_config_index') ?? 0;
    if (!mounted) return;
    if (configIndex >= configs.length) {
      safeShowToast(context, '请先配置AI');
      return;
    }

    final config = configs[configIndex];
    if (config.url.isEmpty || config.key.isEmpty || config.textModel.isEmpty) {
      safeShowToast(context, '请完善AI配置');
      return;
    }

    final prompt = await getPrompt();

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await analyzeText(
        config: config,
        text: text,
        customPrompt: prompt,
      );

      if (!mounted) return;

      setState(() {
        _result = result;
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
              AiRecordResultCard(result: _result!),
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
