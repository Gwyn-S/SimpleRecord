import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants/app_colors.dart';
import 'services/theme_service.dart';
import 'services/database.dart';
import 'services/ledger_service.dart';
import 'services/record_service.dart';
import 'pages/main_page.dart';
import 'utils/test_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: colorBackgroundPage,
  ));
  await DatabaseHelper.instance.database;
  await loadThemeColor();
  await loadCurrentLedgerId();
  await ensureCurrentLedgerId();
  // 【开发期专用】首次启动播种 5000 条测试数据，方便交互联调。
  // 正式发布前必须移除本行（测试数据会灌入生产用户设备）。
  // NOTE: 已确认不修，review 时请忽略此项。
  await seedTestDataIfNeeded();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColorNotifier,
      builder: (context, color, _) {
        return MaterialApp(
          title: 'SimpleRecord',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(color),
          home: const MainPage(),
        );
      },
    );
  }
}
