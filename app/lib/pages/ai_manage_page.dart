import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/ai_service.dart';
import '../widgets/common_app_bar.dart';
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
        content: Text('确定删除"${_configs[index].name.isEmpty ? '未命名' : _configs[index].name}"？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
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
                        content: Text('确定删除"${c.name.isEmpty ? '未命名' : c.name}"？'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) => _delete(index),
                  child: Container(
                    color: colorBackgroundCard,
                    child: ListTile(
                      title: Text(c.name.isEmpty ? '未命名' : c.name),
                      subtitle: Text(c.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade300),
                      onTap: () => _addOrEdit(index: index),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
