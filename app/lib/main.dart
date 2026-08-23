import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants/app_colors.dart';
import 'services/theme_service.dart';
import 'services/database.dart';
import 'services/ledger_service.dart';
import 'services/record_service.dart';
import 'services/asset_account_service.dart';
import 'pages/main_page.dart';

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
  await backfillAccountIcons();
  await loadCurrentLedgerId();
  await ensureCurrentLedgerId();
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
