import 'package:flutter/material.dart';
import '../theme.dart';
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

  void _toggleMenu() {
    setState(() => _menuOpen = !_menuOpen);
  }

  void _closeMenu() {
    if (_menuOpen) setState(() => _menuOpen = false);
  }

  static const _pages = [
    BillsPage(),
    CalendarPage(),
    SizedBox(),
    StatsPage(),
    AssetsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
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
            child: _pages[_tab],
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
        child: ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) {
            return SizedBox(
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
                backgroundColor: color,
                shape: const CircleBorder(),
                elevation: 0,
                child: Icon(
                  _menuOpen ? Icons.close : Icons.add,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
        ),
        child: _buildBottomBar(),
      ),
    );
  }

  Widget _miniFab(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ValueListenableBuilder<Color>(
        valueListenable: themeColorNotifier,
        builder: (context, color, _) {
          return Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return SizedBox(
      height: 64,
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
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) {
            return Column(
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
                              color: selected ? color : const Color(0xFF333333),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                '${DateTime.now().day}',
                                style: TextStyle(
                                  fontSize: selected ? 9 : 8,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? color : const Color(0xFF333333),
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
                        color: selected ? color : const Color(0xFF333333),
                      ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: selected ? 14 : 12,
                    fontWeight: FontWeight.w500,
                    color: selected ? color : const Color(0xFF333333),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
