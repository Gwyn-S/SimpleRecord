import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../models/ai_record_result.dart';
import '../models/asset_account.dart';
import '../services/ai_service.dart';
import '../services/asset_account_service.dart';
import '../utils/toast.dart';
import '../widgets/ai_record_result_card.dart';
import '../widgets/common_app_bar.dart';

class AiTextRecordPage extends StatefulWidget {
  const AiTextRecordPage({super.key});

  @override
  State<AiTextRecordPage> createState() => _AiTextRecordPageState();
}

class _AiTextRecordPageState extends State<AiTextRecordPage> {
  final _textController = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  String? _error;
  List<AiRecordResult> _results = [];
  List<AssetAccount> _accounts = [];

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

    final configIndex = await getConfigIndex('ai_text_config_index');
    if (!mounted) return;
    if (configIndex == null) {
      safeShowToast(context, '请先选择文本模型');
      return;
    }
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
    final accounts = await loadAssetAccounts();

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _accounts = accounts;
    });

    try {
      final results = await analyzeTextList(
        config: config,
        text: text,
        customPrompt: prompt,
        accounts: accounts,
        model: config.textModel,
      );

      if (!mounted) return;

      setState(() {
        _results = results;
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

  Future<void> _saveRecords() async {
    if (_results.isEmpty || _saving) return;
    _saving = true;

    final error = await saveAiResults(_results);
    if (!mounted) return;
    if (error != null) {
      _saving = false;
      safeShowToast(context, error);
      return;
    }
    safeShowToast(context, '已记录${_results.length}笔');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CommonAppBar(title: '文字记账'),
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
            if (_results.isNotEmpty) ...[
              const SizedBox(height: spacingL),
              Expanded(
                child: ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: spacingM),
                  itemBuilder: (_, i) => AiRecordResultCard(result: _results[i], accounts: _accounts),
                ),
              ),
              const SizedBox(height: spacingM),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _saveRecords,
                  child: Text('确认记账${_results.length > 1 ? '(${_results.length}笔)' : ''}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
