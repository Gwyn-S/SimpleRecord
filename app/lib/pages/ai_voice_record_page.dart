import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../models/ai_record_result.dart';
import '../models/asset_account.dart';
import '../models/record.dart';
import '../services/ai_service.dart';
import '../services/asset_account_service.dart';
import '../services/record_service.dart';
import '../services/tencent_asr_service.dart';
import '../services/theme_service.dart';
import '../services/transfer_service.dart';
import '../utils/id.dart';
import '../utils/toast.dart';
import '../widgets/ai_record_result_card.dart';
import '../widgets/common_app_bar.dart';

class AiVoiceRecordPage extends StatefulWidget {
  const AiVoiceRecordPage({super.key});

  @override
  State<AiVoiceRecordPage> createState() => _AiVoiceRecordPageState();
}

class _AiVoiceRecordPageState extends State<AiVoiceRecordPage> {
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _processing = false;
  String? _error;
  String _transcript = '';
  List<AiRecordResult> _results = [];
  List<AssetAccount> _accounts = [];

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await _recorder.isRecording()) return;
    final hasPermission = await _recorder.hasPermission();
    if (!mounted) return;
    if (!hasPermission) {
      safeShowToast(context, '没有麦克风权限');
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() => _recording = true);
    } catch (e) {
      if (!mounted) return;
      safeShowToast(context, '录音启动失败：$e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    final path = await _recorder.stop();
    if (!mounted) return;
    if (path == null) {
      setState(() => _recording = false);
      return;
    }
    setState(() {
      _recording = false;
      _error = null;
      _transcript = '';
      _results = [];
    });
    await _recognize(File(path));
  }

  Future<void> _recognize(File audioFile) async {
    setState(() => _processing = true);
    try {
      final asrConfig = await loadAsrConfig();
      if (!mounted) return;
      if (!asrConfig.isValid) {
        safeShowToast(context, '请先在AI设置配置语音识别密钥');
        setState(() => _processing = false);
        return;
      }

      final configs = await loadAiConfigs();
      if (!mounted) return;
      final textIndex = await getConfigIndex('ai_text_config_index');
      final prompt = await getPrompt();
      final accounts = await loadAssetAccounts();
      if (!mounted) return;
      if (configs.isEmpty) {
        safeShowToast(context, '请先配置AI');
        setState(() => _processing = false);
        return;
      }
      if (textIndex == null || textIndex >= configs.length) {
        safeShowToast(context, '请先选择文本模型');
        setState(() => _processing = false);
        return;
      }
      final config = configs[textIndex];
      if (config.url.isEmpty || config.key.isEmpty || config.textModel.isEmpty) {
        safeShowToast(context, '请完善AI配置');
        setState(() => _processing = false);
        return;
      }

      final transcript = await recognizeSpeech(config: asrConfig, audioFile: audioFile);
      if (!mounted) return;

      final results = await analyzeTextList(
        config: config,
        text: transcript,
        customPrompt: prompt,
        accounts: accounts,
      );
      if (!mounted) return;

      setState(() {
        _transcript = transcript;
        _results = results;
        _accounts = accounts;
        _processing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '识别失败：$e';
        _processing = false;
      });
    } finally {
      if (audioFile.existsSync()) await audioFile.delete();
    }
  }

  Future<void> _saveRecords() async {
    if (_results.isEmpty) return;

    for (final result in _results) {
      if (result.isTransfer) {
        if (result.fromAccountId.isEmpty || result.toAccountId.isEmpty) {
          safeShowToast(context, '转账账户缺失，请手动记账');
          return;
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

    if (!mounted) return;
    safeShowToast(context, '已记录${_results.length}笔');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CommonAppBar(title: '语音记账'),
      backgroundColor: colorBackgroundPage,
      body: Padding(
        padding: const EdgeInsets.all(spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRecordButton(),
            if (_processing) ...[
              const SizedBox(height: spacingL),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: spacingM),
              const Center(child: Text('识别中...')),
            ],
            if (_error != null) ...[
              const SizedBox(height: spacingL),
              Text(_error!, style: const TextStyle(color: colorDelete)),
            ],
            if (_transcript.isNotEmpty) ...[
              const SizedBox(height: spacingL),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(spacingL),
                child: Text(_transcript, style: const TextStyle(fontSize: 16)),
              ),
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

  Widget _buildRecordButton() {
    final primary = Theme.of(context).extension<AppThemeColors>()!.primary;
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: _recording ? primary.withValues(alpha: 0.15) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _recording ? primary : colorDivider,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _recording ? Icons.graphic_eq : Icons.mic,
              size: 48,
              color: _recording ? primary : colorTextSecondary,
            ),
            const SizedBox(height: spacingS),
            Text(
              _recording ? '松开结束，正在录音...' : '按住说话',
              style: TextStyle(
                fontSize: 16,
                color: _recording ? primary : colorTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}