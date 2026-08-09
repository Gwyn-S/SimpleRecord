import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../services/theme_service.dart';
import 'bills_page.dart';
import 'calendar_page.dart';
import 'stats_page.dart';
import 'assets_page.dart';
import 'manual_entry_page.dart';
import 'add_asset_account_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _tab = 0;
  bool _menuOpen = false;
  final int _todayDay = DateTime.now().day;

  void _toggleMenu() {
    setState(() => _menuOpen = !_menuOpen);
  }

  void _closeMenu() {
    if (_menuOpen) setState(() => _menuOpen = false);
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
        child: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      ),
      body: Stack(
        children: [
          GestureDetector(
            onTap: _closeMenu,
            behavior: HitTestBehavior.translucent,
            child: IndexedStack(
              index: _tab,
              children: _pages,
            ),
          ),
          if (_menuOpen)
            Positioned(
              bottom: 68,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: MediaQuery.of(context).size.width / 2 - 100,
                      top: 2,
                      // TODO: 接入拍照记账功能
                      child: _miniFab(Icons.edit, _closeMenu),
                    ),
                    Positioned(
                      left: MediaQuery.of(context).size.width / 2 - 22,
                      top: -18,
                      // TODO: 接入语音记账功能
                      child: _miniFab(Icons.mic, _closeMenu),
                    ),
                    Positioned(
                      right: MediaQuery.of(context).size.width / 2 - 100,
                      top: 2,
                      // TODO: 接入扫码记账功能
                      child: _miniFab(Icons.camera_alt, _closeMenu),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: GestureDetector(
        onLongPress: _tab == 4 ? null : _toggleMenu,
        child: SizedBox(
          width: 60,
          height: 60,
          child: FloatingActionButton(
            onPressed: _menuOpen ? _closeMenu : () {
              if (_tab == 4) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AddAssetAccountPage()));
              } else {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ManualEntryPage()));
              }
            },
            backgroundColor: Theme.of(context).extension<AppThemeColors>()!.primary,
            shape: const CircleBorder(),
            elevation: 0,
            child: Icon(
              _menuOpen ? Icons.close : Icons.add,
              color: colorTextOnPrimary,
              size: iconSizeFab,
            ),
          ),
        ),
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

  Widget _miniFab(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: sizeIconContainer,
        height: sizeIconContainer,
        decoration: BoxDecoration(
          color: Theme.of(context).extension<AppThemeColors>()!.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: colorTextOnPrimary, size: iconSizeDefault),
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
