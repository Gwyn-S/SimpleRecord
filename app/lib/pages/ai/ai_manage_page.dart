import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/ai/ai_config.dart';
import '../../services/ai/ai_service.dart';
import '../../widgets/common/common_app_bar.dart';
import 'ai_config_detail_page.dart';

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
        builder: (_) =>
            AiConfigDetailPage(config: index != null ? _configs[index] : null),
      ),
    );
    _load();
  }

  void _remove(int index) {
    _configs.removeAt(index);
    saveAiConfigs(_configs);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
        title: 'AI 管理',
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
                return Dismissible(
                  key: ValueKey(index),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        content: Text(
                          '确定删除"${c.name.isEmpty ? '未命名' : c.name}"？',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              '删除',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) => _remove(index),
                  child: Container(
                    color: colorBackgroundCard,
                    child: GestureDetector(
                      onTap: () => _addOrEdit(index: index),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: spacingL,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.name.isEmpty ? '未命名' : c.name,
                                style: textPickerItem,
                              ),
                            ),
                            ..._featureTags(c),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Colors.grey.shade300,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  List<Widget> _featureTags(AiConfig c) {
    final tags = <Widget>[];
    void add(IconData icon) {
      tags.add(
        Container(
          margin: const EdgeInsets.only(left: 8),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: colorTextSecondary),
        ),
      );
    }

    if (c.textModel.isNotEmpty) add(Icons.chat_bubble_outline);
    if (c.visionModel.isNotEmpty) add(Icons.visibility_outlined);
    if (c.voiceModel.isNotEmpty) add(Icons.mic_outlined);
    return tags;
  }
}
