import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../models/ai/ai_record_result.dart';
import '../../models/data/asset_account.dart';
import '../../services/ai/ai_service.dart';
import '../../services/data/asset_account_service.dart';
import '../../utils/toast.dart';
import 'ai_record_result_card.dart';

/// 文字记账面板：输入框 + 识别 + 结果确认。
/// 页面与底部弹层共用，[autofocus] 让弹层打开时自动拉起键盘。
/// [initialText] 可预填转写文本供语音记账复用。
class AiTextRecordPanel extends StatefulWidget {
  const AiTextRecordPanel({
    super.key,
    this.autofocus = false,
    this.initialText,
    this.autoAnalyze = false,
  });

  final bool autofocus;
  final String? initialText;

  /// 打开后自动触发识别（语音记账复用）。
  final bool autoAnalyze;

  @override
  State<AiTextRecordPanel> createState() => _AiTextRecordPanelState();
}

class _AiTextRecordPanelState extends State<AiTextRecordPanel> {
  final _textController = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  String? _error;
  List<AiRecordResult> _results = [];
  List<AssetAccount> _accounts = [];

  @override
  void initState() {
    super.initState();
    final hasInitialText =
        widget.initialText != null && widget.initialText!.isNotEmpty;
    if (hasInitialText) {
      _textController.text = widget.initialText!;
    }
    if (widget.autoAnalyze && hasInitialText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _analyze();
      });
    }
  }

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(spacingL),
          child: TextField(
            controller: _textController,
            maxLines: 3,
            autofocus: widget.autofocus,
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
        const SizedBox(height: spacingM),
        SizedBox(
          height: 44,
          child: FilledButton(
            onPressed: _loading
                ? null
                : () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    _analyze();
                  },
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('识别'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: spacingM),
          Text(_error!, style: const TextStyle(color: colorDelete)),
        ],
        if (_results.isNotEmpty)
          Expanded(
            child: AiRecordResultSection(
              results: _results,
              accounts: _accounts,
              onSave: _saveRecords,
            ),
          ),
      ],
    );
  }
}