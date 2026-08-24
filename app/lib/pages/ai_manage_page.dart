import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/ai_service.dart';
import '../services/theme_service.dart';
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
        builder: (_) => AiConfigDetailPage(
          config: index != null ? _configs[index] : null,
        ),
      ),
    );
    _load();
  }

  Future<void> _delete(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除"${_configs[index].name.isEmpty ? '未命名' : _configs[index].name}"？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
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
                    subtitle: Text(c.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _addOrEdit(index: index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20),
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
