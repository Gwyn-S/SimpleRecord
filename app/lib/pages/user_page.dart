import 'package:flutter/material.dart';
import '../theme.dart';

class UserPage extends StatelessWidget {
  const UserPage({super.key});

  static const _colors = [
    Color(0xFFF44336),
    Color(0xFFFF5722),
    Color(0xFFFF9800),
    Color(0xFFFFC107),
    Color(0xFFFFEB3B),
    Color(0xFF8BC34A),
    Color(0xFF4CAF50),
    Color(0xFF009688),
    Color(0xFF00BCD4),
    Color(0xFF03A9F4),
    Color(0xFF2196F3),
    Color(0xFF3F51B5),
    Color(0xFF673AB7),
    Color(0xFF9C27B0),
    Color(0xFFE91E63),
  ];

  void _applyColor(BuildContext context, Color c) {
    themeColorNotifier.value = c;
    saveThemeColor(c);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('用户'), backgroundColor: Colors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: '', onPressed: () => Navigator.pop(context))),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          _settingsItem(
            title: '主题颜色',
            trailing: ValueListenableBuilder<Color>(
              valueListenable: themeColorNotifier,
              builder: (_, color, _2) => Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            onTap: () => _showColorPicker(context),
          ),
        ],
      ),
    );
  }

  Widget _settingsItem({
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
            const Spacer(),
            if (trailing != null) trailing,
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        contentPadding: const EdgeInsets.all(24),
        content: SizedBox(
          width: 224,
          child: ValueListenableBuilder<Color>(
            valueListenable: themeColorNotifier,
            builder: (context, currentColor, _) {
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  ..._colors.map((c) {
                    final selected = c == currentColor;
                    return GestureDetector(
                      onTap: () => _applyColor(context, c),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                        child: selected
                            ? const Icon(Icons.check, color: Colors.white, size: 22)
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
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFFF44336),
                            Color(0xFFFF9800),
                            Color(0xFFFFEB3B),
                            Color(0xFF4CAF50),
                            Color(0xFF2196F3),
                            Color(0xFF9C27B0),
                          ],
                        ),
                      ),
                      child: currentColor != _colors.first && !_colors.contains(currentColor)
                          ? const Icon(Icons.check, color: Colors.white, size: 22)
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
            contentPadding: const EdgeInsets.all(24),
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
                  const SizedBox(height: 20),
                  _sliderRow('色相', Slider(
                    value: hsv.hue, min: 0, max: 360,
                    activeColor: hsv.toColor(),
                    onChanged: (v) => setDialogState(() => hsv = hsv.withHue(v)),
                  )),
                  _sliderRow('饱和度', Slider(
                    value: hsv.saturation, min: 0, max: 1,
                    activeColor: hsv.toColor(),
                    onChanged: (v) => setDialogState(() => hsv = hsv.withSaturation(v)),
                  )),
                  _sliderRow('亮度', Slider(
                    value: hsv.value, min: 0, max: 1,
                    activeColor: hsv.toColor(),
                    onChanged: (v) => setDialogState(() => hsv = hsv.withValue(v)),
                  )),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => _applyColor(context, hsv.toColor()),
                    child: Container(
                      width: double.infinity,
                      height: 40,
                      decoration: BoxDecoration(
                        color: hsv.toColor(),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: const Text('确定', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
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
        SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF999999)))),
        Expanded(child: slider),
      ],
    );
  }
}
