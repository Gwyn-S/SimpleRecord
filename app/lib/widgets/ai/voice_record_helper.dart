import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../constants/app_dimensions.dart';
import '../../services/ai/tencent_asr_service.dart';
import '../../services/core/theme_service.dart';

/// 语音录音助手：长按录音、松开结束，全程展示遮罩提示与转写进度。
/// 把录音 + 遮罩 + 转写封装在 widgets 层，页面只需编排。
class VoiceRecordHelper {
  final AudioRecorder _recorder = AudioRecorder();
  OverlayEntry? _overlay;
  OverlayEntry? _transcribingOverlay;
  OverlayState? _overlayState;

  bool _recording = false;
  bool get isRecording => _recording;

  Future<void> dispose() async {
    await _removeOverlay();
    await _removeTranscribingOverlay();
    await _recorder.dispose();
  }

  /// 开始录音并显示「正在录音」遮罩。返回是否成功开启。
  Future<bool> start(BuildContext context) async {
    if (_recording) return false;
    final overlayState = Overlay.maybeOf(context);
    final granted = await _recorder.hasPermission();
    if (!granted || overlayState == null) return false;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (_) {
      return false;
    }
    if (_overlay != null) return true;
    _overlayState = overlayState;
    final overlay = OverlayEntry(
      builder: (_) => VoiceRecordingOverlay(),
    );
    _overlay = overlay;
    overlayState.insert(overlay);
    _recording = true;
    return true;
  }

  /// 取消录音：丢弃音频并移除遮罩。
  Future<void> cancel() async {
    await _stop(discard: true);
  }

  /// 结束录音：转写文本并移除遮罩。返回转写结果，取消/失败返回 null。
  Future<String?> finish() async {
    return _stop(discard: false);
  }

  Future<String?> _stop({required bool discard}) async {
    if (!_recording && _overlay == null) return null;
    _recording = false;
    await _removeOverlay();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    final file = path == null ? null : File(path);
    if (file == null) return null;
    try {
      if (discard) return null;
      _showTranscribingOverlay();
      final asrConfig = await loadAsrConfig();
      return await recognizeSpeech(config: asrConfig, audioFile: file);
    } catch (e) {
      await _removeTranscribingOverlay();
      final msg = e is Exception ? '$e'.replaceFirst('Exception: ', '') : '$e';
      _showTranscribingOverlay(error: msg);
      await Future.delayed(const Duration(seconds: 2));
      return null;
    } finally {
      await _removeTranscribingOverlay();
      if (file.existsSync()) await file.delete();
    }
  }

  void _showTranscribingOverlay({String? error}) {
    if (_transcribingOverlay != null || _overlayState == null) return;
    final overlay = OverlayEntry(
      builder: (_) => _TranscribingOverlay(error: error),
    );
    _transcribingOverlay = overlay;
    _overlayState!.insert(overlay);
  }

  Future<void> _removeTranscribingOverlay() async {
    _transcribingOverlay?.remove();
    _transcribingOverlay = null;
  }

  Future<void> _removeOverlay() async {
    _overlay?.remove();
    _overlay = null;
  }
}

/// 录音遮罩：整页灰化 + 声波动画 + 「松开结束」文字提示。
class VoiceRecordingOverlay extends StatefulWidget {
  const VoiceRecordingOverlay({super.key});

  @override
  State<VoiceRecordingOverlay> createState() => _VoiceRecordingOverlayState();
}

class _VoiceRecordingOverlayState extends State<VoiceRecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor =
        Theme.of(context).extension<AppThemeColors>()!.primary;
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.35),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: spacingL),
                child: SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _SineWavePainter(
                      animation: _controller,
                      color: themeColor,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: spacingL),
              Text(
                '正在录音，松开结束',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SineWavePainter extends CustomPainter {
  final Animation<double> animation;
  final double strokeWidth;
  final Color color;

  _SineWavePainter({
    required this.animation,
    required this.color,
    this.strokeWidth = 3,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final periodCount = 3.0;
    final amplitudeFactor = 0.38;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final midY = size.height / 2;
    final amp = size.height * amplitudeFactor;
    final step = 4.0;
    final theta = 2 * 3.14159 * periodCount;
    final travel = t * 2 * 3.14159;

    for (var x = 0.0; x <= size.width; x += step) {
      final ratio = x / size.width;
      final y = midY + sin(ratio * theta + travel) * amp;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SineWavePainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// 转写遮罩：灰层 + 转圈 + 「正在识别」提示；失败时显示错误信息。
class _TranscribingOverlay extends StatelessWidget {
  final String? error;

  const _TranscribingOverlay({this.error});

  @override
  Widget build(BuildContext context) {
    final themeColor =
        Theme.of(context).extension<AppThemeColors>()!.primary;
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.45),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error == null) ...[
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: themeColor,
                  ),
                ),
                const SizedBox(height: spacingL),
                Text(
                  '正在识别，请稍候',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                    height: 1.2,
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: spacingXL),
                  child: Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}