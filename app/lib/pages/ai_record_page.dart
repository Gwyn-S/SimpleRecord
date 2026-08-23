import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../services/settings.dart';
import '../utils/toast.dart';
import 'ai_manage_page.dart';

const _aiBookkeepingKey = 'ai_bookkeeping_enabled';
const _aiTextConfigKey = 'ai_text_config_index';
const _aiImageConfigKey = 'ai_image_config_index';
const _aiVoiceConfigKey = 'ai_voice_config_index';
const _aiPromptKey = 'ai_prompt';

const _defaultPrompt = '你是一个记账助手。用户会输入消费或收入的描述，你需要解析出：isExpense(是否支出，true/false)、categoryName(分类名称)、amountCents(金额，单位分)、remark(备注)、date(日期，格式yyyy-MM-dd，今天则返回空字符串)。只返回JSON，不要其他内容。可用分类：餐饮、交通、购物、娱乐、居住、医疗、教育、通讯、服饰、美容、运动、旅行、宠物、数码、Gifts、其他、工资、奖金、兼职、理财、红包、报销、其他。';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final configs = await loadAiConfigs();
    final enabled = await Settings.getBool(_aiBookkeepingKey) ?? false;
    final textIndex = await Settings.getInt(_aiTextConfigKey);
    final imageIndex = await Settings.getInt(_aiImageConfigKey);
    final voiceIndex = await Settings.getInt(_aiVoiceConfigKey);
    final prompt = await Settings.getString(_aiPromptKey) ?? '';
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _enabled = enabled;
      _textConfigIndex = textIndex;
      _imageConfigIndex = imageIndex;
      _voiceConfigIndex = voiceIndex;
      _promptController.text = prompt.isEmpty ? _defaultPrompt : prompt;
    });
  }

  Future<void> _toggle(bool value) async {
    await Settings.setBool(_aiBookkeepingKey, value);
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  String _configLabel(AiConfig c) {
    final name = c.name.isEmpty ? '未命名' : c.name;
    return name;
  }

  Widget _buildConfigSelector({
    required String label,
    required int? selectedIndex,
    required ValueChanged<int?> onChanged,
    bool showVision = false,
    bool showVoice = false,
  }) {
    final selectedName = selectedIndex != null && selectedIndex < _configs.length
        ? _configLabel(_configs[selectedIndex])
        : '未选择';

    return GestureDetector(
      onTap: _configs.isEmpty
          ? null
          : () => _showConfigPicker(
                selectedIndex: selectedIndex,
                onChanged: onChanged,
                showVision: showVision,
                showVoice: showVoice,
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
                color: selectedIndex != null ? Colors.black : Colors.grey,
              ),
            ),
            const SizedBox(width: spacingS),
            Icon(Icons.chevron_right, size: iconSizeMedium, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  void _showConfigPicker({
    required int? selectedIndex,
    required ValueChanged<int?> onChanged,
    required bool showVision,
    required bool showVoice,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectedIndex != null)
                ListTile(
                  title: const Text('取消选择', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    onChanged(null);
                    Navigator.pop(ctx);
                  },
                ),
              ...List.generate(_configs.length, (i) {
                final c = _configs[i];
                String modelInfo = '';
                if (showVision && c.visionModel.isNotEmpty) {
                  modelInfo = ' · ${c.visionModel}';
                } else if (showVoice && c.voiceModel.isNotEmpty) {
                  modelInfo = ' · ${c.voiceModel}';
                } else if (c.textModel.isNotEmpty) {
                  modelInfo = ' · ${c.textModel}';
                }
                return ListTile(
                  title: Text(_configLabel(c) + modelInfo),
                  trailing: selectedIndex == i
                      ? Icon(Icons.check, color: Theme.of(context).extension<AppThemeColors>()!.primary)
                      : null,
                  onTap: () {
                    onChanged(i);
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
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 记账'),
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
                GestureDetector(
                  onTap: () => _toggle(!_enabled),
                  child: Icon(
                    _enabled ? Icons.toggle_on : Icons.toggle_off,
                    size: 40,
                    color: _enabled ? themeColor : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          _settingsItem(
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
            selectedIndex: _textConfigIndex,
            onChanged: (v) async {
              if (v != null) {
                await Settings.setInt(_aiTextConfigKey, v);
              } else {
                await Settings.remove(_aiTextConfigKey);
              }
              setState(() => _textConfigIndex = v);
            },
          ),
          _buildConfigSelector(
            label: '图片模型',
            selectedIndex: _imageConfigIndex,
            onChanged: (v) async {
              if (v != null) {
                await Settings.setInt(_aiImageConfigKey, v);
              } else {
                await Settings.remove(_aiImageConfigKey);
              }
              setState(() => _imageConfigIndex = v);
            },
            showVision: true,
          ),
          _buildConfigSelector(
            label: '语音模型',
            selectedIndex: _voiceConfigIndex,
            onChanged: (v) async {
              if (v != null) {
                await Settings.setInt(_aiVoiceConfigKey, v);
              } else {
                await Settings.remove(_aiVoiceConfigKey);
              }
              setState(() => _voiceConfigIndex = v);
            },
            showVoice: true,
          ),
          _buildPromptField(),
        ],
      ),
    );
  }

  Widget _settingsItem({required String title, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: spacingL),
        height: 56,
        child: Row(
          children: [
            Text(title, style: textListItem),
            const Spacer(),
            Icon(Icons.chevron_right, size: iconSizeMedium, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
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
                  size: iconSizeMedium,
                  color: Colors.grey.shade300,
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
    await Settings.setString(_aiPromptKey, _promptController.text);
    if (!mounted) return;
    safeShowToast(context, '保存成功');
  }

  void _resetPrompt() {
    setState(() => _promptController.text = _defaultPrompt);
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
