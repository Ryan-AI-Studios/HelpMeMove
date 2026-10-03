import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const HelpMeMoveApp());
}

class HelpMeMoveApp extends StatefulWidget {
  const HelpMeMoveApp({super.key});

  @override
  State<HelpMeMoveApp> createState() => _HelpMeMoveAppState();
}

class _HelpMeMoveAppState extends State<HelpMeMoveApp> {
  late final GoRouter _router = buildHelpMeMoveRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HelpMeMove',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      highContrastTheme: AppTheme.highContrastLight(),
      highContrastDarkTheme: AppTheme.highContrastDark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
