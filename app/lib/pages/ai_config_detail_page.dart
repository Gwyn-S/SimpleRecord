import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/ai_config.dart';
import '../services/ai_service.dart';
import '../services/theme_service.dart';
import '../utils/toast.dart';

class AiConfigDetailPage extends StatefulWidget {
  final AiConfig? config;

  const AiConfigDetailPage({super.key, this.config});

  @override
  State<AiConfigDetailPage> createState() => _AiConfigDetailPageState();
}

class _AiConfigDetailPageState extends State<AiConfigDetailPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  late final TextEditingController _textModelController;
  late final TextEditingController _visionModelController;
  late final TextEditingController _voiceModelController;
  bool _showKey = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.config?.name ?? '');
    _urlController = TextEditingController(text: widget.config?.url ?? '');
    _keyController = TextEditingController(text: widget.config?.key ?? '');
    _textModelController = TextEditingController(
      text: widget.config?.textModel ?? '',
    );
    _visionModelController = TextEditingController(
      text: widget.config?.visionModel ?? '',
    );
    _voiceModelController = TextEditingController(
      text: widget.config?.voiceModel ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    _textModelController.dispose();
    _visionModelController.dispose();
    _voiceModelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final allEmpty =
        _nameController.text.isEmpty &&
        _urlController.text.isEmpty &&
        _keyController.text.isEmpty &&
        _textModelController.text.isEmpty &&
        _visionModelController.text.isEmpty &&
        _voiceModelController.text.isEmpty;
    if (allEmpty) {
      showToast(context, '配置为空');
      return;
    }

    final config = AiConfig(
      name: _nameController.text,
      url: _urlController.text,
      key: _keyController.text,
      textModel: _textModelController.text,
      visionModel: _visionModelController.text,
      voiceModel: _voiceModelController.text,
    );

    final configs = await loadAiConfigs();
    final existIndex = configs.indexWhere((c) => c.name == widget.config?.name);
    if (existIndex >= 0) {
      configs[existIndex] = config;
    } else {
      configs.add(config);
    }
    await saveAiConfigs(configs);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _test() async {
    if (_nameController.text.isEmpty) {
      showToast(context, '请填写 AI 名称');
      return;
    }
    if (_urlController.text.isEmpty) {
      showToast(context, '请填写 Base URL');
      return;
    }
    if (_keyController.text.isEmpty) {
      showToast(context, '请填写 API Key');
      return;
    }
    if (_textModelController.text.isEmpty &&
        _visionModelController.text.isEmpty &&
        _voiceModelController.text.isEmpty) {
      showToast(context, '请填写至少一个模型');
      return;
    }

    setState(() => _testing = true);
    try {
      await testAiConnection(
        url: _urlController.text,
        key: _keyController.text,
      );
      if (!mounted) return;
      showToast(context, '测试成功');
    } catch (e) {
      if (!mounted) return;
      showToast(context, '测试失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config != null ? '编辑 AI' : '添加 AI'),
        backgroundColor: themeColor,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: colorBackgroundPage,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSection('AI 配置', [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'AI 名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: spacingM),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: spacingM),
              TextField(
                controller: _keyController,
                obscureText: !_showKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showKey ? Icons.visibility_off : Icons.visibility,
                      size: iconSizeDefault,
                    ),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: spacingXL),
            _buildSection('模型配置', [
              TextField(
                controller: _textModelController,
                decoration: const InputDecoration(
                  labelText: '文本模型',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: spacingM),
              TextField(
                controller: _visionModelController,
                decoration: const InputDecoration(
                  labelText: '视觉模型',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: spacingM),
              TextField(
                controller: _voiceModelController,
                decoration: const InputDecoration(
                  labelText: '语音模型',
                  border: OutlineInputBorder(),
                ),
              ),
            ]),
            const SizedBox(height: spacingXL),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: _testing ? null : _test,
                      child: _testing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('测试'),
                    ),
                  ),
                ),
                const SizedBox(width: spacingM),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('保存'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(spacingL),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textListItem),
          const SizedBox(height: spacingM),
          ...children,
        ],
      ),
    );
  }
}
