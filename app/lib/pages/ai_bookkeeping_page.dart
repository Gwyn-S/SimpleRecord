import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../services/settings.dart';
import 'ai_manage_page.dart';

const _aiBookkeepingKey = 'ai_bookkeeping_enabled';
const _aiTextModelKey = 'ai_text_model';
const _aiImageModelKey = 'ai_image_model';
const _aiVoiceModelKey = 'ai_voice_model';
const _aiPromptKey = 'ai_prompt';

class AiBookkeepingPage extends StatefulWidget {
  const AiBookkeepingPage({super.key});

  @override
  State<AiBookkeepingPage> createState() => _AiBookkeepingPageState();
}

class _AiBookkeepingPageState extends State<AiBookkeepingPage> {
  bool _enabled = false;
  final _textModelController = TextEditingController();
  final _imageModelController = TextEditingController();
  final _voiceModelController = TextEditingController();
  final _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _textModelController.dispose();
    _imageModelController.dispose();
    _voiceModelController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final enabled = await Settings.getBool(_aiBookkeepingKey) ?? false;
    final textModel = await Settings.getString(_aiTextModelKey) ?? '';
    final imageModel = await Settings.getString(_aiImageModelKey) ?? '';
    final voiceModel = await Settings.getString(_aiVoiceModelKey) ?? '';
    final prompt = await Settings.getString(_aiPromptKey) ?? '';
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _textModelController.text = textModel;
      _imageModelController.text = imageModel;
      _voiceModelController.text = voiceModel;
      _promptController.text = prompt;
    });
  }

  Future<void> _toggle(bool value) async {
    await Settings.setBool(_aiBookkeepingKey, value);
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  Future<void> _save(String key, String value) async {
    await Settings.setString(key, value);
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
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiManagePage()),
            ),
          ),
          _buildTextField('文本模型', _textModelController, _aiTextModelKey),
          _buildTextField('图片模型', _imageModelController, _aiImageModelKey),
          _buildTextField('语音模型', _voiceModelController, _aiVoiceModelKey),
          _buildTextField('提示词', _promptController, _aiPromptKey),
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

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String settingsKey,
  ) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: spacingL),
      height: 56,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: textListItem),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: spacingM),
              ),
              style: textListItem,
              onChanged: (value) => _save(settingsKey, value),
            ),
          ),
        ],
      ),
    );
  }
}
