import 'package:flutter/material.dart';

import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/auto_backup_service.dart';

/// 自动备份设置组件：点击弹窗选择频率，点即选中并关闭。
/// 按 [scene]（webdav / local）独立持久化。
class AutoBackupTile extends StatefulWidget {
  const AutoBackupTile({
    super.key,
    required this.scene,
    this.title = '自动备份',
  });

  /// 场景，用于读写独立的持久化 key。
  final AutoBackupScene scene;

  /// 按钮行左侧标题。
  final String title;

  @override
  State<AutoBackupTile> createState() => _AutoBackupTileState();
}

class _AutoBackupTileState extends State<AutoBackupTile> {
  AutoBackupFrequency _frequency = AutoBackupFrequency.closed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final frequency = await AutoBackupService.frequency(widget.scene);
    if (!mounted) return;
    setState(() => _frequency = frequency);
  }

  String get _label => '${widget.title}：${_frequency.label}';

  Future<void> _openSettings() async {
    final f = await showDialog<AutoBackupFrequency>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        contentPadding: const EdgeInsets.fromLTRB(spacingXL, spacingXL, spacingXL, spacingS),
        children: [
          RadioGroup<AutoBackupFrequency>(
            groupValue: _frequency,
            onChanged: (v) => Navigator.pop(dialogContext, v),
            child: Column(
              children: AutoBackupFrequency.values
                  .map(
                    (f) => RadioListTile<AutoBackupFrequency>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.label, style: textBody),
                      value: f,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (f == null || f == _frequency) return;
    final enabled = !f.isClosed;
    await AutoBackupService.save(
      widget.scene,
      enabled: enabled,
      freq: f,
    );
    setState(() => _frequency = f);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: _openSettings,
        icon: const Icon(Icons.schedule_outlined),
        label: Text(_label),
      ),
    );
  }
}
