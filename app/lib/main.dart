import 'package:flutter/material.dart';
import 'theme.dart';
import 'services/database.dart';
import 'services/book_service.dart';
import 'services/record_service.dart';
import 'pages/main_page.dart';
import 'utils/test_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;
  await loadThemeColor();
  await loadCurrentBookId();
  await ensureCurrentBookId();
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
