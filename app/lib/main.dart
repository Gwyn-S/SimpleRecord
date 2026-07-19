import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'constants/app_colors.dart';
import 'theme.dart';
import 'models/record.dart';
import 'pages/main_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadThemeColor();
  await loadCurrentBookId();
  initRecordsListener();
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
          title: 'KeepBook',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: colorBackgroundCard,
            colorScheme: ColorScheme.fromSeed(seedColor: color),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              },
            ),
          ),
          home: const MainPage(),
        );
      },
    );
  }
}
