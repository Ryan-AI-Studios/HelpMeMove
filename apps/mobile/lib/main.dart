import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final StorageController storage = StorageController.production();
  final String initialLocation = await storage.open();
  runApp(
    HelpMeMoveApp(
      initialLocation: initialLocation,
      recovery: StorageRecovery(onRetry: storage.open, onReset: storage.reset),
      readStore: () => storage.store,
    ),
  );
}

class HelpMeMoveApp extends StatefulWidget {
  const HelpMeMoveApp({
    super.key,
    this.initialLocation = '/',
    this.recovery,
    this.store,
    this.readStore,
  });

  final String initialLocation;
  final StorageRecovery? recovery;
  final ProfileStore? store;
  final ProfileStore? Function()? readStore;

  @override
  State<HelpMeMoveApp> createState() => _HelpMeMoveAppState();
}

class _HelpMeMoveAppState extends State<HelpMeMoveApp> {
  late final GoRouter _router = buildHelpMeMoveRouter(
    initialLocation: widget.initialLocation,
    recovery: widget.recovery,
    store: widget.store,
    readStore: widget.readStore,
    storageBlocked: widget.initialLocation != '/',
  );

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
