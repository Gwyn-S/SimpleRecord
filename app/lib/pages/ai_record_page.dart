import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../models/ai_config.dart';
import '../models/tencent_asr_config.dart';
import '../services/ai_service.dart';
import '../services/tencent_asr_service.dart';
import '../services/theme_service.dart';
import '../services/settings.dart';
import '../utils/toast.dart';
import '../widgets/common_app_bar.dart';
import '../widgets/settings_item.dart';
import 'ai_manage_page.dart';

class AiRecordPage extends StatefulWidget {
  const AiRecordPage({super.key});

  @override
  State<AiRecordPage> createState() => _AiRecordPageState();
}

class _AiRecordPageState extends State<AiRecordPage> {
  bool _enabled = false;
  int? _textConfigIndex;
  int? _imageConfigIndex;
  int? _voiceConfigIndex;
  final _promptController = TextEditingController();
  List<AiConfig> _configs = [];
  bool _promptExpanded = false;
  bool _asrExpanded = false;
  bool _asrTesting = false;
  final _secretIdController = TextEditingController();
  final _secretKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _secretIdController.dispose();
    _secretKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final configs = await loadAiConfigs();
    final enabled = await Settings.getBool(aiRecordKey) ?? false;
    final textIndex = await getConfigIndex('ai_text_config_index');
    final imageIndex = await getConfigIndex('ai_image_config_index');
    final voiceIndex = await getConfigIndex('ai_voice_config_index');
    final prompt = await getPrompt();
    final asr = await loadAsrConfig();
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _enabled = enabled;
      _textConfigIndex = textIndex;
      _imageConfigIndex = imageIndex;
      _voiceConfigIndex = voiceIndex;
      _promptController.text = prompt.isEmpty ? defaultAiPrompt : prompt;
      _secretIdController.text = asr.secretId;
      _secretKeyController.text = asr.secretKey;
    });
  }

  Future<void> _toggle(bool value) async {
    await Settings.setBool(aiRecordKey, value);
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  String _configLabel(AiConfig c) {
    final name = c.name.isEmpty ? '未命名' : c.name;
    return name;
  }

  bool _supports(AiConfig c, String feature) =>
      _modelField(c, feature).isNotEmpty;

  String _modelField(AiConfig c, String feature) {
    switch (feature) {
      case 'text':
        return c.textModel;
      case 'vision':
        return c.visionModel;
      case 'voice':
        return c.voiceModel;
    }
    return '';
  }

  Widget _buildConfigSelector({
    required String label,
    required String feature,
    required int? selectedIndex,
    required ValueChanged<int?> onChanged,
  }) {
    final candidates = <int>[];
    for (var i = 0; i < _configs.length; i++) {
      if (_supports(_configs[i], feature)) candidates.add(i);
    }
    final selectedName =
        selectedIndex != null && candidates.contains(selectedIndex)
        ? _configLabel(_configs[selectedIndex])
        : '未选择';

    return GestureDetector(
      onTap: candidates.isEmpty
          ? null
          : () => _showConfigPicker(
              feature: feature,
              candidates: candidates,
              selectedIndex: selectedIndex,
              onChanged: onChanged,
            ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: spacingL),
        height: 56,
        child: Row(
          children: [
            Text(label, style: textListItem),
            const Spacer(),
            Text(
              selectedName,
              style: TextStyle(
                fontSize: 16,
                color:
                    selectedIndex != null && candidates.contains(selectedIndex)
                    ? Colors.black
                    : Colors.grey,
              ),
            ),
            const SizedBox(width: spacingS),
            Icon(
              Icons.chevron_right,
              size: iconSizeDefault,
              color: colorTextSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _showConfigPicker({
    required String feature,
    required List<int> candidates,
    required int? selectedIndex,
    required ValueChanged<int?> onChanged,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectedIndex != null && candidates.contains(selectedIndex))
                ListTile(
                  title: const Text(
                    '取消选择',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    onChanged(null);
                    Navigator.pop(ctx);
                  },
                ),
              ...List.generate(candidates.length, (j) {
                final origIndex = candidates[j];
                final c = _configs[origIndex];
                final modelInfo = _modelField(c, feature);
                return ListTile(
                  title: Text(
                    _configLabel(c) +
                        (modelInfo.isEmpty ? '' : ' · $modelInfo'),
                  ),
                  trailing: selectedIndex == origIndex
                      ? Icon(
                          Icons.check,
                          color: Theme.of(
                            context,
                          ).extension<AppThemeColors>()!.primary,
                        )
                      : null,
                  onTap: () {
                    onChanged(origIndex);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CommonAppBar(title: 'AI 记账'),
      backgroundColor: colorBackgroundPage,
      body: ListView(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: spacingL),
            height: 56,
            child: Row(
              children: [
                const Text('启用 AI 记账', style: textListItem),
                const Spacer(),
                Switch(
                  value: _enabled,
                  onChanged: _toggle,
                  splashRadius: 0,
                  activeTrackColor: Theme.of(
                    context,
                  ).extension<AppThemeColors>()!.primary,
                  inactiveTrackColor: Colors.grey.shade300,
                  thumbColor: WidgetStateProperty.all(Colors.white),
                ),
              ],
            ),
          ),
          SettingsItem(
            title: 'AI 配置',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiManagePage()),
              );
              _loadSettings();
            },
          ),
          _buildConfigSelector(
            label: '文本模型',
            feature: 'text',
            selectedIndex: _textConfigIndex,
            onChanged: (v) async {
              await setConfigIndex('ai_text_config_index', v);
              setState(() => _textConfigIndex = v);
            },
          ),
          _buildConfigSelector(
            label: '视觉模型',
            feature: 'vision',
            selectedIndex: _imageConfigIndex,
            onChanged: (v) async {
              await setConfigIndex('ai_image_config_index', v);
              setState(() => _imageConfigIndex = v);
            },
          ),
          _buildConfigSelector(
            label: '语音模型',
            feature: 'voice',
            selectedIndex: _voiceConfigIndex,
            onChanged: (v) async {
              await setConfigIndex('ai_voice_config_index', v);
              setState(() => _voiceConfigIndex = v);
            },
          ),
          _buildAsrField(),
          _buildPromptField(),
        ],
      ),
    );
  }

  Widget _buildAsrField() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _asrExpanded = !_asrExpanded),
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: spacingL),
            height: 56,
            child: Row(
              children: [
                const Text('语音识别密钥', style: textListItem),
                const Spacer(),
                Icon(
                  _asrExpanded ? Icons.expand_less : Icons.chevron_right,
                  size: iconSizeDefault,
                  color: colorTextSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_asrExpanded)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(spacingL, 0, spacingL, spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _secretIdController,
                  decoration: const InputDecoration(
                    labelText: 'SecretId',
                    hintText: '腾讯云 API 密钥 ID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: spacingM),
                TextField(
                  controller: _secretKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'SecretKey',
                    hintText: '腾讯云 API 密钥 Key',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: spacingM),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _asrTesting ? null : _testAsr,
                        child: _asrTesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('测试'),
                      ),
                    ),
                    const SizedBox(width: spacingM),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saveAsr,
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _saveAsr() async {
    final id = _secretIdController.text.trim();
    final key = _secretKeyController.text.trim();
    if (id.isEmpty && key.isEmpty) {
      safeShowToast(context, '配置为空');
      return;
    }
    await saveAsrConfig(TencentAsrConfig(secretId: id, secretKey: key));
    if (!mounted) return;
    safeShowToast(context, '保存成功');
  }

  Future<void> _testAsr() async {
    final id = _secretIdController.text.trim();
    final key = _secretKeyController.text.trim();
    if (id.isEmpty || key.isEmpty) {
      safeShowToast(context, '请填写 SecretId 和 SecretKey');
      return;
    }
    setState(() => _asrTesting = true);
    try {
      await testAsr(TencentAsrConfig(secretId: id, secretKey: key));
      if (!mounted) return;
      safeShowToast(context, '语音识别连通正常');
    } catch (e) {
      if (!mounted) return;
      safeShowToast(context, '测试失败：$e');
    } finally {
      if (mounted) setState(() => _asrTesting = false);
    }
  }

  Widget _buildPromptField() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _promptExpanded = !_promptExpanded),
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: spacingL),
            height: 56,
            child: Row(
              children: [
                const Text('提示词', style: textListItem),
                const Spacer(),
                Icon(
                  _promptExpanded ? Icons.expand_less : Icons.chevron_right,
                  size: iconSizeDefault,
                  color: colorTextSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_promptExpanded)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(spacingL, 0, spacingL, spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _promptController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: '自定义AI记账提示词',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: spacingM),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showPromptHelp(),
                        child: const Text('说明'),
                      ),
                    ),
                    const SizedBox(width: spacingM),
                    Expanded(
                      child: FilledButton(
                        onPressed: _savePrompt,
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: spacingS),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _resetPrompt,
                    child: const Text('恢复默认'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _savePrompt() async {
    await Settings.setString('ai_prompt', _promptController.text);
    if (!mounted) return;
    safeShowToast(context, '保存成功');
  }

  void _resetPrompt() {
    setState(() => _promptController.text = defaultAiPrompt);
  }

  void _showPromptHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示词说明'),
        content: const Text(
          '提示词用于指导AI如何解析记账内容。\n\n'
          'AI会根据提示词返回JSON格式数据，包含：\n'
          '- isExpense: 是否支出\n'
          '- categoryName: 分类名称\n'
          '- amountCents: 金额（分）\n'
          '- remark: 备注\n'
          '- date: 日期\n\n'
          '可用分类：餐饮、交通、购物、娱乐、居住、医疗、教育等。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
