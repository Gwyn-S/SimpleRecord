import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../models/ai/ai_record_result.dart';
import '../../models/data/asset_account.dart';
import '../../services/ai/ai_service.dart';
import '../../services/data/asset_account_service.dart';
import '../../utils/toast.dart';
import '../common/full_image_viewer.dart';
import 'ai_record_result_card.dart';

/// 图片记账面板：选图 + 识别 + 结果确认。
/// [initialImage] 预填选中的图片，[autoAnalyze] 打开后自动识别。
class AiImageRecordPanel extends StatefulWidget {
  const AiImageRecordPanel({
    super.key,
    this.initialImage,
    this.autoAnalyze = false,
  });

  final File? initialImage;
  final bool autoAnalyze;

  @override
  State<AiImageRecordPanel> createState() => _AiImageRecordPanelState();
}

class _AiImageRecordPanelState extends State<AiImageRecordPanel> {
  final _picker = ImagePicker();
  File? _imageFile;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  List<AiRecordResult> _results = [];
  List<AssetAccount> _accounts = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialImage != null) {
      _imageFile = widget.initialImage;
    }
    if (widget.autoAnalyze && _imageFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _analyze();
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _imageFile = File(picked.path);
      _results = [];
      _error = null;
    });
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              title: const Text('相册'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _analyze() async {
    if (_imageFile == null) {
      safeShowToast(context, '请先选择图片');
      return;
    }

    final configs = await loadAiConfigs();
    if (!mounted) return;
    if (configs.isEmpty) {
      safeShowToast(context, '请先配置AI');
      return;
    }

    final configIndex = await getConfigIndex('ai_image_config_index');
    if (!mounted) return;
    if (configIndex == null) {
      safeShowToast(context, '请先选择视觉模型');
      return;
    }
    if (configIndex >= configs.length) {
      safeShowToast(context, '请先配置AI');
      return;
    }

    final config = configs[configIndex];
    if (config.url.isEmpty ||
        config.key.isEmpty ||
        config.visionModel.isEmpty) {
      safeShowToast(context, '请完善AI配置（需设置视觉模型）');
      return;
    }

    final prompt = await getPrompt();
    final accounts = await loadAssetAccounts();

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _accounts = accounts;
    });

    try {
      final results = await analyzeImage(
        config: config,
        imageFile: _imageFile!,
        customPrompt: prompt,
        accounts: accounts,
      );

      if (!mounted) return;

      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'API请求失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _saveRecords() async {
    if (_results.isEmpty || _saving) return;
    _saving = true;

    final error = await saveAiResults(_results);
    if (!mounted) return;
    if (error != null) {
      _saving = false;
      safeShowToast(context, error);
      return;
    }
    safeShowToast(context, '已记录${_results.length}笔');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: _showImagePicker,
          child: Container(
            height: 160,
            color: Colors.white,
            child: _imageFile != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(_imageFile!, fit: BoxFit.cover),
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FullImageViewer(
                                  imagePaths: [_imageFile!.path],
                                  initialIndex: 0,
                                  showDelete: false,
                                  onDelete: (_) => Navigator.pop(context),
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.fullscreen,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 40,
                        color: colorTextSecondary,
                      ),
                      const SizedBox(height: spacingS),
                      Text(
                        '选择图片',
                        style: TextStyle(color: colorTextSecondary),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: spacingM),
        SizedBox(
          height: 44,
          child: FilledButton(
            onPressed: _loading
                ? null
                : () {
                    _analyze();
                  },
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('识别'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: spacingM),
          Text(_error!, style: const TextStyle(color: colorDelete)),
        ],
        if (_results.isNotEmpty)
          Expanded(
            child: AiRecordResultSection(
              results: _results,
              accounts: _accounts,
              onSave: _saveRecords,
            ),
          ),
      ],
    );
  }
}