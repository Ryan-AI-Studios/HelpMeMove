import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/account/account_auth.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/program/program_document.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await AccountAuth.start();
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
    this.previewSafetyView,
    this.previewProgram,
    this.previewSession,
    this.adaptTheme,
  });

  final String initialLocation;
  final StorageRecovery? recovery;
  final ProfileStore? store;
  final ProfileStore? Function()? readStore;

  /// Test-only constructed view. Production leaves this null.
  final SafetyView? previewSafetyView;

  /// Test-only plan. Production leaves this null.
  final LocalProgram? previewProgram;

  /// Test-only session document. Production leaves this null.
  final String? previewSession;

  /// Test-only theme adjustment, used so captures can load a real font.
  /// Production leaves this null.
  final ThemeData Function(ThemeData theme)? adaptTheme;

  @override
  State<HelpMeMoveApp> createState() => _HelpMeMoveAppState();
}

class _HelpMeMoveAppState extends State<HelpMeMoveApp> {
  ThemeMode _themeMode = ThemeMode.system;
  var _appearanceEpoch = 0;

  late final GoRouter _router = buildHelpMeMoveRouter(
    initialLocation: widget.initialLocation,
    recovery: widget.recovery,
    store: widget.store,
    readStore: widget.readStore,
    storageBlocked: _storageBlocked,
    previewSafetyView: widget.previewSafetyView,
    previewProgram: widget.previewProgram,
    previewSession: widget.previewSession,
    onAppearanceSaved: _applyAppearance,
  );

  bool get _storageBlocked =>
      widget.initialLocation == '/storage-failure' ||
      widget.initialLocation == '/key-loss';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadAppearance());
    });
  }

  Future<void> _loadAppearance() async {
    if (_storageBlocked) {
      return;
    }
    final ProfileStore? store = widget.store ?? widget.readStore?.call();
    if (store == null || store.openDatabaseFile == null) {
      return;
    }
    final int epoch = _appearanceEpoch;
    try {
      final String? choice = await store.loadAppearanceChoice();
      if (!mounted || epoch != _appearanceEpoch) {
        return;
      }
      setState(() {
        _themeMode = themeModeForAppearance(choice);
      });
    } on Object {
      // A failed or unreadable read leaves the system theme in place.
    }
  }

  void _applyAppearance(String choice) {
    _appearanceEpoch += 1;
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = themeModeForAppearance(choice);
    });
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData Function(ThemeData theme) adapt =
        widget.adaptTheme ?? (ThemeData theme) => theme;
    return MaterialApp.router(
      title: 'HelpMeMove',
      theme: adapt(AppTheme.light()),
      darkTheme: adapt(AppTheme.dark()),
      highContrastTheme: adapt(AppTheme.highContrastLight()),
      highContrastDarkTheme: adapt(AppTheme.highContrastDark()),
      themeMode: _themeMode,
      routerConfig: _router,
    );
  }
}

ThemeMode themeModeForAppearance(String? choice) {
  switch (choice) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}
