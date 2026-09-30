import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../constants/app_colors.dart';
import '../services/core/theme_service.dart';
import '../services/core/database.dart';
import '../services/data/ledger_service.dart';
import '../services/data/record_service.dart';
import '../services/data/category_service.dart';
import '../services/data/asset_account_service.dart';
import '../services/core/author_service.dart';
import '../services/core/update_installer.dart';
import '../services/core/update_service.dart';
import '../services/cloud/auto_backup_service.dart';
import '../services/cloud/supabase_service.dart';
import '../services/cloud/sync_service.dart';
import '../utils/log.dart';
import '../pages/main_page.dart';

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
  await UpdateService.instance.loadInstalledVersion();
  await backfillAccountIcons();
  await loadCurrentLedgerId();
  // 先让 Supabase 会话就绪（若已配置且曾登录，会同步恢复邮箱会话），
  // 再校验当前账本：避免启动时未登录而把上次打开的共享账本误判为失效重置。
  await SupabaseManager.instance.init();
  await ensureCurrentLedgerId();
  // 创建/选中当前账本后再加载其分类缓存（首次启动会先建默认账本并写入种子）。
  await loadCategoryCache();
  // 注册远端分类变更回调：共享账本成员新增/删除分类时本地即时刷新。
  initCategorySync();
  // 预热头像缓存目录，使列表头像可同步命中本地缓存（首帧即显示）。
  await AuthorService.instance.initAvatarCache();
  // 加载记账条目作者显示偏好（昵称/头像）到进程内存，供列表首帧按用户选择渲染。
  await AuthorService.instance.loadRecordAuthorDisplay();
  // 后台启动云同步：不阻塞首屏渲染（Supabase 未配置或未登录邮箱时静默跳过）。
  // 失败仅打日志兜底，避免多次 async 步骤失败成为无人接住的全局异常。
  SyncService.instance.start().catchError((Object e) {
    appLog('[sync] start failed: $e');
    return false;
  });
  // 自动备份：启动时对已启用且到期的场景执行一次（WebDAV / 本地），失败仅打日志兜底。
  AutoBackupService.runAll().catchError((Object e) {
    appLog('[auto backup] run failed: $e');
  });
  // 启动清理：删除已装版本的更新包缓存（≤ 当前安装版本的永不再用），
  // 下载好未安装的更高版本保留供下次复用。不阻塞首帧，失败静默。
  unawaited(UpdateInstaller.cleanupInstalledApk());
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
          title: '简记',
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
