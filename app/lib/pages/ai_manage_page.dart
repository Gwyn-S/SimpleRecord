import 'dart:convert';

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../services/settings.dart';
import 'ai_config_detail_page.dart';

const _aiConfigsKey = 'ai_configs';

class AiConfig {
  String name;
  String url;
  String key;
  String textModel;
  String visionModel;
  String voiceModel;

  AiConfig({
    required this.name,
    required this.url,
    required this.key,
    this.textModel = '',
    this.visionModel = '',
    this.voiceModel = '',
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'url': url,
    'key': key,
    'textModel': textModel,
    'visionModel': visionModel,
    'voiceModel': voiceModel,
  };

  factory AiConfig.fromMap(Map<String, dynamic> m) => AiConfig(
    name: m['name'] as String? ?? '',
    url: m['url'] as String? ?? '',
    key: m['key'] as String? ?? '',
    textModel: m['textModel'] as String? ?? '',
    visionModel: m['visionModel'] as String? ?? '',
    voiceModel: m['voiceModel'] as String? ?? '',
  );
}

Future<List<AiConfig>> loadAiConfigs() async {
  final json = await Settings.getString(_aiConfigsKey);
  if (json == null || json.isEmpty) return [];
  try {
    final list = jsonDecode(json) as List;
    return list.map((e) => AiConfig.fromMap(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveAiConfigs(List<AiConfig> configs) async {
  final json = jsonEncode(configs.map((c) => c.toMap()).toList());
  await Settings.setString(_aiConfigsKey, json);
}

class AiManagePage extends StatefulWidget {
  const AiManagePage({super.key});

  @override
  State<AiManagePage> createState() => _AiManagePageState();
}

class _AiManagePageState extends State<AiManagePage> {
  List<AiConfig> _configs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final configs = await loadAiConfigs();
    if (!mounted) return;
    setState(() => _configs = configs);
  }

  void _addOrEdit({int? index}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiConfigDetailPage(
          config: index != null ? _configs[index] : null,
          index: index,
        ),
      ),
    );
    _load();
  }

  Future<void> _delete(int index) async {
    _configs.removeAt(index);
    await saveAiConfigs(_configs);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 管理'),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '',
            onPressed: () => _addOrEdit(),
          ),
        ],
      ),
      backgroundColor: colorBackgroundPage,
      body: _configs.isEmpty
          ? const SizedBox()
          : ListView.builder(
              itemCount: _configs.length,
              itemBuilder: (context, index) {
                final c = _configs[index];
                return Container(
                  color: colorBackgroundCard,
                  child: ListTile(
                    title: Text(c.name.isEmpty ? '未命名' : c.name),
                    subtitle: Text(c.url, style: textItemSub, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: iconSizeMedium),
                          onPressed: () => _addOrEdit(index: index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: iconSizeMedium),
                          onPressed: () => _delete(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
