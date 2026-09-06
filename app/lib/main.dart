import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'constants/app_colors.dart';
import 'services/theme_service.dart';
import 'services/database.dart';
import 'services/ledger_service.dart';
import 'services/record_service.dart';
import 'services/asset_account_service.dart';
import 'services/author_service.dart';
import 'services/auto_backup_service.dart';
import 'services/sync_service.dart';
import 'utils/log.dart';
import 'pages/main_page.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: colorBackgroundPage,
    ),
  );
  await DatabaseHelper.instance.database;
  await loadThemeColor();
  await backfillAccountIcons();
  await loadCurrentLedgerId();
  await ensureCurrentLedgerId();
  // 预热头像缓存目录，使列表头像可同步命中本地缓存（首帧即显示）。
  await AuthorService.instance.initAvatarCache();
  // 加载记账条目作者显示偏好（昵称/头像）到进程内存，供列表首帧按用户选择渲染。
  await AuthorService.instance.loadRecordAuthorDisplay();
  // 后台启动云同步：不阻塞首屏渲染（Supabase 未配置时静默跳过）。
  // 失败仅打日志兜底，避免多次 async 步骤失败成为无人接住的全局异常。
  SyncService.instance.start().catchError((Object e) {
    appLog('[sync] start failed: $e');
    return false;
  });
  // 自动备份：启动时对已启用且到期的场景执行一次（WebDAV / 本地），失败仅打日志兜底。
  AutoBackupService.runAll().catchError((Object e) {
    appLog('[auto backup] run failed: $e');
  });
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
          navigatorObservers: [routeObserver],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          locale: const Locale('zh', 'CN'),
        );
      },
    );
  }
}
