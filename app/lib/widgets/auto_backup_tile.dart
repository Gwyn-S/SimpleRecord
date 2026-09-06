import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/auto_backup_service.dart';
import '../services/theme_service.dart';

/// 自动备份设置组件：开关 + 频率下拉（每天/每3天/每周/每月）。
/// 开关与频率按 [prefix]（webdav_ / local_）独立持久化，UI 结束后自动落盘。
class AutoBackupTile extends StatefulWidget {
  const AutoBackupTile({
    super.key,
    required this.prefix,
    this.title = '自动备份',
  });

  /// 场景前缀，用于读写独立的持久化 key。
  final String prefix;

  /// 开关行左侧标题。
  final String title;

  @override
  State<AutoBackupTile> createState() => _AutoBackupTileState();
}

class _AutoBackupTileState extends State<AutoBackupTile> {
  bool _enabled = false;
  AutoBackupFrequency _frequency = AutoBackupFrequency.daily;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await AutoBackupService.isEnabled(widget.prefix);
    final frequency = await AutoBackupService.frequency(widget.prefix);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _frequency = frequency;
    });
  }

  Future<void> _onToggle(bool value) async {
    setState(() => _enabled = value);
    await AutoBackupService.save(widget.prefix, enabled: value);
  }

  Future<void> _onFrequencyChanged(AutoBackupFrequency f) async {
    setState(() => _frequency = f);
    await AutoBackupService.save(widget.prefix, freq: f);
  }

  @override
  Widget build(BuildContext context) {
    final titleText = _enabled
        ? '${widget.title}：${_frequency.label}'
        : widget.title;
    final title = Text(
      titleText,
      style: textListItem,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Row(
      children: [
        Expanded(
          child: _enabled
              ? PopupMenuButton<AutoBackupFrequency>(
                  tooltip: '',
                  menuPadding: EdgeInsets.zero,
                  onSelected: _onFrequencyChanged,
                  itemBuilder: (context) => [
                    for (final f in AutoBackupFrequency.values)
                      PopupMenuItem<AutoBackupFrequency>(
                        value: f,
                        height: 36,
                        padding: EdgeInsets.zero,
                        child: Row(
                          children: [
                            Expanded(child: Text(f.label, style: textBody)),
                            if (_frequency == f)
                              Icon(
                                Icons.check,
                                size: 18,
                                color: Theme.of(
                                  context,
                                ).extension<AppThemeColors>()!.primary,
                              ),
                          ],
                        ),
                      ),
                  ],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Flexible(child: title),
                      Icon(
                        Icons.arrow_drop_down,
                        size: iconSizeDefault,
                        color: colorTextSecondary,
                      ),
                    ],
                  ),
                )
              : title,
        ),
        Switch(
          value: _enabled,
          onChanged: _onToggle,
        ),
      ],
    );
  }
}
