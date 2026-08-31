import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../models/ai_record_result.dart';
import '../models/asset_account.dart';
import '../services/ai_service.dart';
import '../services/asset_account_service.dart';
import '../utils/toast.dart';
import '../widgets/ai_record_result_card.dart';
import '../widgets/common_app_bar.dart';

class AiImageRecordPage extends StatefulWidget {
  const AiImageRecordPage({super.key});

  @override
  State<AiImageRecordPage> createState() => _AiImageRecordPageState();
}

class _AiImageRecordPageState extends State<AiImageRecordPage> {
  File? _imageFile;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  List<AiRecordResult> _results = [];
  List<AssetAccount> _accounts = [];
  final _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _imageFile = File(picked.path);
      _results = [];
      _error = null;
    });
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
    if (config.url.isEmpty || config.key.isEmpty || config.visionModel.isEmpty) {
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
    return Scaffold(
      appBar: const CommonAppBar(title: '图片记账'),
      backgroundColor: colorBackgroundPage,
      body: Padding(
        padding: const EdgeInsets.all(spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildImagePicker(),
            const SizedBox(height: spacingM),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: (_loading || _imageFile == null) ? null : _analyze,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return Container(
      height: 200,
      color: Colors.white,
      child: _imageFile != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.file(_imageFile!, fit: BoxFit.cover),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _imageFile = null;
                      _results = [];
                      _error = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPickButton(Icons.camera_alt, '拍照', ImageSource.camera),
                _buildPickButton(Icons.photo_library, '相册', ImageSource.gallery),
              ],
            ),
    );
  }

  Widget _buildPickButton(IconData icon, String label, ImageSource source) {
    return GestureDetector(
      onTap: () => _pickImage(source),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: colorTextSecondary),
          const SizedBox(height: spacingS),
          Text(label, style: const TextStyle(color: colorTextSecondary)),
        ],
      ),
    );
  }
}
