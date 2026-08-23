import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../services/theme_service.dart';
import '../services/settings.dart';
import '../main.dart';
import '../widgets/speed_dial_fab.dart';
import 'bills_page.dart';
import 'calendar_page.dart';
import 'stats_page.dart';
import 'assets_page.dart';
import 'manual_entry_page.dart';
import 'add_asset_account_page.dart';
import 'ai_text_record_page.dart';

const _aiBookkeepingKey = 'ai_bookkeeping_enabled';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with RouteAware {
  int _tab = 0;
  bool _aiEnabled = false;
  final int _todayDay = DateTime.now().day;

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
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadAiSetting();
  }

  Future<void> _loadAiSetting() async {
    final enabled = await Settings.getBool(_aiBookkeepingKey) ?? false;
    if (!mounted) return;
    setState(() => _aiEnabled = enabled);
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
      body: IndexedStack(
        index: _tab,
        children: _pages,
      ),
      floatingActionButton: SpeedDialFAB(
        onPressed: () {
          if (_tab == 4) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AddAssetAccountPage()));
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ManualEntryPage()));
          }
        },
        icon: Icons.add,
        enabled: _tab != 4 && _aiEnabled,
        actions: [
          SpeedDialAction(
            icon: Icons.edit,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AiTextBookkeepingPage()));
            },
          ),
          SpeedDialAction(
            icon: Icons.mic,
            onTap: () {
              // TODO: 接入语音记账功能
            },
          ),
          SpeedDialAction(
            icon: Icons.camera_alt,
            onTap: () {
              // TODO: 接入拍照记账功能
            },
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: colorBackgroundCard,
          border: Border(top: BorderSide(color: colorDivider, width: borderWidthDefault)),
        ),
        child: _buildBottomBar(),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SizedBox(
      height: heightBottomNav,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _tabItem(0, Icons.home_outlined, Icons.home, '账单'),
          _tabItem(1, Icons.calendar_today_outlined, Icons.calendar_today, '日历'),
          const SizedBox(width: 56),
          _tabItem(3, Icons.bar_chart_outlined, Icons.bar_chart, '统计'),
          _tabItem(4, Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, '资产'),
        ],
      ),
    );
  }

  Widget _tabItem(int index, IconData outlineIcon, IconData fillIcon, String label) {
    final selected = _tab == index;
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
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
