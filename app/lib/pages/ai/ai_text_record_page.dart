import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../widgets/ai/ai_text_record_panel.dart';
import '../../widgets/common/common_app_bar.dart';

class AiTextRecordPage extends StatefulWidget {
  const AiTextRecordPage({super.key});

  @override
  State<AiTextRecordPage> createState() => _AiTextRecordPageState();
}

class _AiTextRecordPageState extends State<AiTextRecordPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CommonAppBar(title: '文字记账'),
      backgroundColor: colorBackgroundPage,
      body: Padding(
        padding: const EdgeInsets.all(spacingL),
        child: const AiTextRecordPanel(autofocus: true),
      ),
    );
  }
}