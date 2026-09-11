import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../services/core/theme_service.dart';
import '../../utils/navigation.dart';
import '../../widgets/common/settings_item.dart';
import '../ai/ai_record_page.dart';

class UserPage extends StatelessWidget {
  const UserPage({super.key});

  void _applyColor(BuildContext context, Color c) {
    themeColorNotifier.value = c;
    saveThemeColor(c);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户'),
        backgroundColor: Theme.of(context).extension<AppThemeColors>()!.primary,
        foregroundColor: colorTextOnPrimary,
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
          SettingsItem(title: '预算中心', onTap: () => openBudget(context)),
          SettingsItem(title: '标签管理', onTap: () => openTagManage(context)),
          SettingsItem(
            title: 'AI 记账',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiRecordPage()),
            ),
          ),
          SettingsItem(
            title: '主题颜色',
            trailing: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Theme.of(context).extension<AppThemeColors>()!.primary,
                shape: BoxShape.circle,
              ),
            ),
            onTap: () => _showColorPicker(context),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        contentPadding: const EdgeInsets.all(spacingXXL),
        content: SizedBox(
          width: 224,
          child: Builder(
            builder: (context) {
              final currentColor = Theme.of(
                context,
              ).extension<AppThemeColors>()!.primary;
              return Wrap(
                spacing: spacingL,
                runSpacing: spacingL,
                children: [
                  ...themeColorPalette.map((c) {
                    final selected = c == currentColor;
                    return GestureDetector(
                      onTap: () => _applyColor(context, c),
                      child: Container(
                        width: sizeIconContainer,
                        height: sizeIconContainer,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check,
                                color: colorTextOnPrimary,
                                size: iconSizeLarge,
                              )
                            : null,
                      ),
                    );
                  }),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _showCustomColorPicker(context);
                    },
                    child: Container(
                      width: sizeIconContainer,
                      height: sizeIconContainer,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: rainbowGradientColors),
                      ),
                      child:
                          currentColor != themeColorPalette.first &&
                              !themeColorPalette.contains(currentColor)
                          ? const Icon(
                              Icons.check,
                              color: colorTextOnPrimary,
                              size: iconSizeLarge,
                            )
                          : null,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showCustomColorPicker(BuildContext context) {
    HSVColor hsv = HSVColor.fromColor(themeColorNotifier.value);

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            contentPadding: const EdgeInsets.all(spacingXXL),
            content: SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: hsv.toColor(),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: spacingXL),
                  _sliderRow(
                    '色相',
                    Slider(
                      value: hsv.hue,
                      min: 0,
                      max: 360,
                      activeColor: hsv.toColor(),
                      onChanged: (v) =>
                          setDialogState(() => hsv = hsv.withHue(v)),
                    ),
                  ),
                  _sliderRow(
                    '饱和度',
                    Slider(
                      value: hsv.saturation,
                      min: 0,
                      max: 1,
                      activeColor: hsv.toColor(),
                      onChanged: (v) =>
                          setDialogState(() => hsv = hsv.withSaturation(v)),
                    ),
                  ),
                  _sliderRow(
                    '亮度',
                    Slider(
                      value: hsv.value,
                      min: 0,
                      max: 1,
                      activeColor: hsv.toColor(),
                      onChanged: (v) =>
                          setDialogState(() => hsv = hsv.withValue(v)),
                    ),
                  ),
                  const SizedBox(height: spacingM),
                  GestureDetector(
                    onTap: () => _applyColor(context, hsv.toColor()),
                    child: Container(
                      width: double.infinity,
                      height: 40,
                      decoration: BoxDecoration(
                        color: hsv.toColor(),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '确定',
                        style: TextStyle(
                          color: colorTextOnPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sliderRow(String label, Widget slider) {
    return Row(
      children: [
        SizedBox(width: 50, child: Text(label, style: textItemSub)),
        Expanded(child: slider),
      ],
    );
  }
}
