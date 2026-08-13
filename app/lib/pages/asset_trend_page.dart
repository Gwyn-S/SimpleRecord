import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../models/asset_account.dart';
import '../services/theme_service.dart';

class AssetTrendPage extends StatelessWidget {
  final AssetAccount account;

  const AssetTrendPage({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('趋势图'),
        backgroundColor: themeColor,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const Center(
        child: Text('趋势图（开发中）', style: textHint),
      ),
    );
  }
}
