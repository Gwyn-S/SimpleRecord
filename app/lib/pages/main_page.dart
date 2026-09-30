import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../services/core/theme_service.dart';
import '../services/core/settings.dart';
import '../services/ai/ai_service.dart';
import '../main.dart';
import '../widgets/common/speed_dial_fab.dart';
import '../widgets/ai/ai_text_record_panel.dart';
import '../widgets/ai/ai_image_record_panel.dart';
import '../widgets/ai/voice_record_helper.dart';
import 'record/bills_page.dart';
import 'record/calendar_page.dart';
import 'record/stats_page.dart';
import 'asset/assets_page.dart';
import 'record/add_record_page.dart';
import 'asset/add_asset_account_page.dart';

/// FAB 直径（须与 SpeedDialFab 内部一致）。
const double _kFabSize = 60;

/// FAB 左右各留的呼吸位，避免贴住相邻 tab。
const double _kFabGap = 8;

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with RouteAware {
  int _tab = 0;
  bool _aiEnabled = false;
  int get _todayDay => DateTime.now().day;
  static const _voiceActionIndex = 1;
  final _voiceHelper = VoiceRecordHelper();

  @override
  void initState() {
    super.initState();
    _loadAiSetting();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _voiceHelper.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadAiSetting();
  }

  Future<void> _loadAiSetting() async {
    final enabled = await Settings.getBool(aiRecordKey) ?? false;
    if (!mounted) return;
    setState(() => _aiEnabled = enabled);
  }

  Future<void> _openTextRecord() async {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: colorBackgroundPage,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: spacingXL,
          vertical: spacingL,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.6,
          ),
          child: const Padding(
            padding: EdgeInsets.all(spacingL),
            child: AiTextRecordPanel(autofocus: true),
          ),
        ),
      ),
    );
  }

  Future<void> _startVoiceRecord() async {
    final started = await _voiceHelper.start(context);
    if (started) {
      // 开始录音，提示已显示；松手时 _finishVoiceRecord 处理转写
    }
  }

  /// hover 到麦克风 action 时开始录音；移开不停止，松手才停。
  void _onVoiceHoverChanged(int? index) {
    if (index == _voiceActionIndex && !_voiceHelper.isRecording) {
      _startVoiceRecord();
    }
  }

  Future<void> _finishVoiceRecord() async {
    if (!_voiceHelper.isRecording) return;
    final text = await _voiceHelper.finish();
    if (!mounted) return;
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: colorBackgroundPage,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: spacingXL,
          vertical: spacingL,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.6,
          ),
          child: Padding(
            padding: const EdgeInsets.all(spacingL),
            child: AiTextRecordPanel(
              autofocus: false,
              initialText: trimmed,
              autoAnalyze: true,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openImageRecord() async {
    final controller = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('拍照'),
              leading: const Icon(Icons.photo_camera_outlined),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              title: const Text('相册'),
              leading: const Icon(Icons.photo_library_outlined),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await controller.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null) return;
    if (!mounted) return;

    final file = File(picked.path);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: colorBackgroundPage,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: spacingXL,
          vertical: spacingL,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.7,
          ),
          child: Padding(
            padding: const EdgeInsets.all(spacingL),
            child: AiImageRecordPanel(
              initialImage: file,
              autoAnalyze: true,
            ),
          ),
        ),
      ),
    );
  }

  static final _pages = const [
    BillsPage(),
    CalendarPage(),
    SizedBox(),
    StatsPage(),
    AssetsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorBackgroundPage,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(0),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      body: IndexedStack(index: _tab, children: _pages),
      floatingActionButton: SpeedDialFAB(
        onPressed: () {
          if (_tab == 4) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddAssetAccountPage()),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddRecordPage()),
            );
          }
        },
        icon: Icons.add,
        longPressEnabled: _tab != 4 && _aiEnabled,
        onHoverChanged: _onVoiceHoverChanged,
        onRelease: () {
          if (_voiceHelper.isRecording) {
            _finishVoiceRecord();
            return true;
          }
          return false;
        },
        actions: [
          SpeedDialAction(
            icon: Icons.edit,
            onTap: () async {
              await _openTextRecord();
            },
          ),
          const SpeedDialAction(
            icon: Icons.mic,
            onTap: null,
          ),
          SpeedDialAction(
            icon: Icons.camera_alt,
            onTap: () async {
              await _openImageRecord();
            },
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Material(
        color: colorBackgroundCard,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: colorDivider, width: borderWidthDefault),
            ),
          ),
          child: _buildBottomBar(),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SizedBox(
      height: heightBottomNav,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avail = constraints.maxWidth;

          // 中间给 FAB 留出 直径+两端呼吸位，剩余宽度由 4 个 tab 平分，铺满整行。
          final fabSlot = _kFabSize + _kFabGap * 2;
          final tabSize = (avail - fabSlot) / 4;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _tabItem(0, Icons.home_outlined, Icons.home, '账单', tabSize),
              _tabItem(
                1,
                Icons.calendar_today_outlined,
                Icons.calendar_today,
                '日历',
                tabSize,
              ),
              SizedBox(width: fabSlot),
              _tabItem(
                3,
                Icons.bar_chart_outlined,
                Icons.bar_chart,
                '统计',
                tabSize,
              ),
              _tabItem(
                4,
                Icons.account_balance_wallet_outlined,
                Icons.account_balance_wallet,
                '资产',
                tabSize,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tabItem(
    int index,
    IconData outlineIcon,
    IconData fillIcon,
    String label,
    double size,
  ) {
    final selected = _tab == index;
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return SizedBox(
      width: size,
      height: heightBottomNav,
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            index == 1
                ? SizedBox(
                    width: selected ? 25 : 22,
                    height: selected ? 25 : 22,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          selected ? fillIcon : outlineIcon,
                          size: selected ? 25 : 22,
                          color: selected ? themeColor : colorTextPrimary,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            '$_todayDay',
                            style: TextStyle(
                              fontSize: selected ? 9 : 8,
                              fontWeight: FontWeight.w700,
                              color: selected ? themeColor : colorTextPrimary,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Icon(
                    selected ? fillIcon : outlineIcon,
                    size: selected ? 25 : 22,
                    color: selected ? themeColor : colorTextPrimary,
                  ),
            const SizedBox(height: spacingXXS),
            Text(
              label,
              style: TextStyle(
                fontSize: selected ? 14 : 12,
                fontWeight: FontWeight.w500,
                color: selected ? themeColor : colorTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
