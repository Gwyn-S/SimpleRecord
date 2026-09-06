import 'dart:math';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../services/theme_service.dart';

class SpeedDialAction {
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  const SpeedDialAction({required this.icon, this.onTap, this.enabled = true});
}

class SpeedDialFAB extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final List<SpeedDialAction> actions;
  final bool enabled;
  final bool longPressEnabled;

  const SpeedDialFAB({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.actions,
    this.enabled = true,
    this.longPressEnabled = true,
  });

  @override
  State<SpeedDialFAB> createState() => _SpeedDialFABState();
}

class _SpeedDialFABState extends State<SpeedDialFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  OverlayEntry? _overlay;
  int? _hovered;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _anim.dispose();
    super.dispose();
  }

  void _show() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;
    final center = pos + Offset(size.width / 2, size.height / 2);

    _overlay = OverlayEntry(builder: (_) => _buildOverlay(center));
    Overlay.of(context).insert(_overlay!);
    _anim.forward();
  }

  void _hide() {
    _anim.reverse().then((_) => _removeOverlay());
    _hovered = null;
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _onMove(Offset globalPos) {
    const angles = [210.0, 270.0, 330.0];
    const dist = 85.0;
    final center =
        (context.findRenderObject() as RenderBox?)?.localToGlobal(
          Offset.zero,
        ) ??
        Offset.zero;
    final btnCenter = center + const Offset(30, 30);

    int? closest;
    double minDist = 50;
    for (int i = 0; i < widget.actions.length && i < angles.length; i++) {
      final rad = angles[i] * pi / 180;
      final target = btnCenter + Offset(dist * cos(rad), dist * sin(rad));
      final d = (globalPos - target).distance;
      if (d < minDist) {
        minDist = d;
        closest = i;
      }
    }
    if (closest != _hovered) {
      _hovered = closest;
      _overlay?.markNeedsBuild();
    }
  }

  void _onEnd() {
    if (_hovered != null && _hovered! < widget.actions.length) {
      final action = widget.actions[_hovered!];
      if (action.enabled && action.onTap != null) action.onTap!();
    }
    _hide();
  }

  Widget _buildOverlay(Offset center) {
    const angles = [210.0, 270.0, 330.0];
    const dist = 85.0;
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        if (_anim.value == 0) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _hide,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3 * _anim.value),
                ),
              ),
            ),
            for (int i = 0; i < widget.actions.length && i < angles.length; i++)
              Builder(
                builder: (_) {
                  final rad = angles[i] * pi / 180;
                  final p = _anim.value;
                  final left = center.dx + p * dist * cos(rad) - 24;
                  final top = center.dy + p * dist * sin(rad) - 24;
                  final hovered = i == _hovered;

                  return Positioned(
                    left: left,
                    top: top,
                    child: Transform.scale(
                      scale: p,
                      child: AnimatedScale(
                        scale: hovered ? 1.15 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Material(
                          color: widget.actions[i].enabled
                              ? themeColor
                              : Colors.grey.shade400,
                          shape: const CircleBorder(),
                          elevation: 4,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              widget.actions[i].icon,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: widget.longPressEnabled ? (_) => _show() : null,
      onLongPressMoveUpdate: widget.longPressEnabled
          ? (d) => _onMove(d.globalPosition)
          : null,
      onLongPressEnd: widget.longPressEnabled ? (_) => _onEnd() : null,
      child: SizedBox(
        width: 60,
        height: 60,
        child: FloatingActionButton(
          onPressed: widget.enabled ? widget.onPressed : null,
          backgroundColor: Theme.of(
            context,
          ).extension<AppThemeColors>()!.primary,
          shape: const CircleBorder(),
          elevation: 0,
          child: Icon(
            widget.icon,
            color: colorTextOnPrimary,
            size: iconSizeFab,
          ),
        ),
      ),
    );
  }
}
