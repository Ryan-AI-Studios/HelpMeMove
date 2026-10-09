import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/account/account_controller.dart';
import 'package:helpmemove/account/account_screen.dart';
import 'package:helpmemove/account/phone_unlock.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/privacy/privacy_screen.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';

const String _evidenceDirectory =
    r'C:\dev\HelpMeMove\Conductor\0021-ConsentExportAndAccountDeletion\ui-evidence';

const String _actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

bool _fontsExist() {
  return File(r'C:\Windows\Fonts\segoeui.ttf').existsSync() &&
      File(r'C:\Windows\Fonts\segoeuib.ttf').existsSync();
}

bool _captureEnabled() {
  return Platform.environment['HMM_UI_EVIDENCE'] == _evidenceDirectory &&
      _fontsExist();
}

void main() {
  setUpAll(() async {
    if (!_captureEnabled()) {
      return;
    }
    TestWidgetsFlutterBinding.ensureInitialized();
    await RustLib.init();
    final FontLoader loader = FontLoader('Segoe UI');
    for (final String path in <String>[
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\segoeuib.ttf',
    ]) {
      final Uint8List bytes = await File(path).readAsBytes();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  const List<String> screens = <String>[
    'export-preview',
    'export-loading',
    'export-success',
    'export-failure',
    'delete-preview',
    'delete-loading',
    'delete-still-here',
    'delete-success-with-session',
    'delete-sign-in-removed',
    'delete-not-replaced-with-session',
    'delete-success',
    'delete-not-replaced',
    'delete-preview-with-session',
    'privacy-lines',
  ];
  for (final String screen in screens) {
    testWidgets('writes 0021 $screen', (WidgetTester tester) async {
      if (!_captureEnabled()) {
        expect(_captureEnabled(), isFalse);
        return;
      }

      final Directory temp = Directory.systemTemp.createTempSync(
        'helpmemove-0021-ui',
      );
      addTearDown(() async {
        if (temp.existsSync()) {
          temp.deleteSync(recursive: true);
        }
      });
      var throwExclude = false;
      final _CaptureStore store = _CaptureStore(
        keys: MemoryProfileKeyStore(),
        supportDirectory: temp,
        clock: () => DateTime.utc(2026, 10, 8),
        random: Random(7),
        excludeFromBackup: (String path) async {
          if (throwExclude &&
              File('$path${Platform.pathSeparator}export.json').existsSync()) {
            throw StateError('exclude failed');
          }
        },
      );
      addTearDown(store.close);
      await tester.runAsync(store.createProfile);
      var sessionOn = false;
      var rpcText = 'unavailable';
      final AccountController account = AccountController(
        store: store,
        phoneUnlock: _ReadyUnlock(),
        sessionReady: () => sessionOn,
        deleteRpc: () async => rpcText,
        signOutAction: () async {},
        stopRefresh: () {},
      );

      Future<void> shootAccount(
        String name,
        String sentence,
        Future<void> Function() prepare, {
        bool tryAgain = false,
        bool expectBack = false,
        bool simulation = false,
      }) async {
        final String label = simulation ? '$name-simulation' : name;
        await _shoot(
          tester,
          name: label,
          sentence: sentence,
          tryAgain: tryAgain,
          expectBack: expectBack,
          boundaryKey: const Key('account-capture'),
          prepare: () async {
            account.accountRouteOpen = true;
            await prepare();
          },
          pump: (Brightness brightness) {
            return tester.pumpWidget(
              _app(
                brightness: brightness,
                home: AccountScreen(controller: account),
              ),
            );
          },
        );
      }

      switch (screen) {
        case 'export-preview':
          await shootAccount(
            'export-preview',
            'Save a copy of this profile?',
            () async {
              account.actorId = null;
              account.confirmInFlight = false;
              await account.openExportPreview();
            },
          );
          break;
        case 'export-loading':
          await shootAccount(
            'export-loading',
            'Preparing the file on this phone.',
            () async {
              account.actorId = null;
              await account.openExportPreview();
              account.confirmInFlight = true;
              account.notifyListeners();
            },
          );
          break;
        case 'export-success':
          await shootAccount('export-success', 'The file stays on this phone until you leave this screen. The copy is not encrypted. If the app closes first, the next launch removes it. This build does not open it or send it.', () async {
            throwExclude = false;
            account.actorId = null;
            account.confirmInFlight = false;
            await account.openExportPreview();
            await account.confirmExport();
          }, expectBack: true);
          break;
        case 'export-failure':
          await shootAccount(
            'export-failure',
            'The file was not prepared.',
            () async {
              throwExclude = true;
              account.actorId = null;
              account.confirmInFlight = false;
              await account.openExportPreview();
              await account.confirmExport();
            },
            tryAgain: true,
            expectBack: true,
          );
          break;
        case 'delete-preview':
          await shootAccount(
            'delete-preview',
            'Remove this profile?',
            () async {
              sessionOn = false;
              account.actorId = null;
              account.confirmInFlight = false;
              store.scriptedRemoval = null;
              await account.openDeletePreview();
            },
          );
          break;
        case 'delete-loading':
          await shootAccount(
            'delete-loading',
            'Removing this profile.',
            () async {
              sessionOn = false;
              account.actorId = null;
              await account.openDeletePreview();
              account.confirmInFlight = true;
              account.rpcDispatched = false;
              account.notifyListeners();
            },
          );
          break;
        case 'delete-still-here':
          await shootAccount(
            'delete-still-here',
            'The profile is still on this phone.',
            () async {
              sessionOn = true;
              rpcText = 'unchanged';
              account.actorId = _actor;
              account.confirmInFlight = false;
              store.scriptedRemoval = null;
              await account.openDeletePreview();
              await account.confirmDelete();
            },
            tryAgain: true,
            expectBack: true,
          );
          break;
        case 'delete-success-with-session':
          await shootAccount(
            'delete-success-with-session',
            'This profile was removed from this phone. This sign-in was removed with it.',
            () async {
              sessionOn = true;
              rpcText = 'deleted';
              account.actorId = _actor;
              account.confirmInFlight = false;
              store.scriptedRemoval = LocalRemoval.replaced;
              await account.openDeletePreview();
              await account.confirmDelete();
            },
            expectBack: true,
            simulation: true,
          );
          break;
        case 'delete-sign-in-removed':
          await shootAccount(
            'delete-sign-in-removed',
            'The sign-in was removed. The profile is still on this phone.',
            () async {
              sessionOn = true;
              rpcText = 'deleted';
              account.actorId = _actor;
              account.confirmInFlight = false;
              store.scriptedRemoval = LocalRemoval.directoryRemained;
              await account.openDeletePreview();
              await account.confirmDelete();
            },
            tryAgain: true,
            expectBack: true,
            simulation: true,
          );
          break;
        case 'delete-not-replaced-with-session':
          await shootAccount(
            'delete-not-replaced-with-session',
            'The profile was removed from this phone. This sign-in was removed with it. A new profile was not opened.',
            () async {
              sessionOn = true;
              rpcText = 'deleted';
              account.actorId = _actor;
              account.confirmInFlight = false;
              store.scriptedRemoval = LocalRemoval.notReplaced;
              await account.openDeletePreview();
              await account.confirmDelete();
            },
            tryAgain: true,
            expectBack: true,
            simulation: true,
          );
          break;
        case 'delete-success':
          await shootAccount(
            'delete-success',
            'This profile was removed from this phone.',
            () async {
              sessionOn = false;
              rpcText = 'unavailable';
              account.actorId = null;
              account.confirmInFlight = false;
              store.scriptedRemoval = LocalRemoval.replaced;
              await account.openDeletePreview();
              await account.confirmDelete();
            },
            expectBack: true,
          );
          break;
        case 'delete-not-replaced':
          await shootAccount(
            'delete-not-replaced',
            'The profile was removed from this phone. A new profile was not opened.',
            () async {
              sessionOn = false;
              rpcText = 'unavailable';
              account.actorId = null;
              account.confirmInFlight = false;
              store.scriptedRemoval = LocalRemoval.notReplaced;
              await account.openDeletePreview();
              await account.confirmDelete();
            },
            tryAgain: true,
            expectBack: true,
          );
          break;
        case 'delete-preview-with-session':
          await shootAccount(
            'delete-preview-with-session',
            'This sign-in is removed with the profile.',
            () async {
              sessionOn = true;
              account.actorId = _actor;
              account.confirmInFlight = false;
              await account.openDeletePreview();
            },
            simulation: true,
          );
          break;
        case 'privacy-lines':
          await _shoot(
            tester,
            name: 'privacy-lines',
            sentence: 'The stated retention for this profile is 3 months. This build removes it only when you choose Remove it.',
            expectBack: true,
            boundaryKey: const Key('privacy-export-capture'),
            tall: true,
            pump: (Brightness brightness) {
              return tester.pumpWidget(
                _app(
                  brightness: brightness,
                  home: RepaintBoundary(
                    key: const Key('privacy-export-capture'),
                    child: ColoredBox(
                      color: brightness == Brightness.dark
                          ? AppColors.dark.surface
                          : AppColors.light.surface,
                      child: PrivacyScreen(store: store, controller: account),
                    ),
                  ),
                ),
              );
            },
          );
          break;
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

ThemeData _captureTheme(ThemeData theme) {
  final Color surface = theme.brightness == Brightness.dark
      ? AppColors.dark.surface
      : AppColors.light.surface;
  return theme.copyWith(
    scaffoldBackgroundColor: surface,
    canvasColor: surface,
    textTheme: theme.textTheme.apply(fontFamily: 'Segoe UI'),
  );
}

Widget _app({required Brightness brightness, required Widget home}) {
  return MaterialApp(
    theme: _captureTheme(AppTheme.light()),
    darkTheme: _captureTheme(AppTheme.dark()),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    themeAnimationDuration: Duration.zero,
    scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
    home: home,
  );
}

Future<void> _shoot(
  WidgetTester tester, {
  required String name,
  required String sentence,
  required Key boundaryKey,
  required Future<void> Function(Brightness brightness) pump,
  Future<void> Function()? prepare,
  bool tryAgain = false,
  bool expectBack = false,
  bool scrollToSentence = false,
  bool tall = false,
}) async {
  final List<({String suffix, Size size, double scale, Brightness brightness})>
  frames = <({String suffix, Size size, double scale, Brightness brightness})>[
    (
      suffix: 'light-390',
      size: tall ? const Size(390, 1400) : const Size(390, 844),
      scale: 1,
      brightness: Brightness.light,
    ),
    (
      suffix: 'dark-390',
      size: tall ? const Size(390, 1400) : const Size(390, 844),
      scale: 1,
      brightness: Brightness.dark,
    ),
    (
      suffix: 'light-840',
      size: tall ? const Size(840, 1400) : const Size(840, 900),
      scale: 1,
      brightness: Brightness.light,
    ),
    (
      suffix: 'light-390-scale-1_3',
      size: tall ? const Size(390, 1600) : const Size(390, 844),
      scale: 1.3,
      brightness: Brightness.light,
    ),
  ];
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  for (final ({String suffix, Size size, double scale, Brightness brightness})
      frame
      in frames) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = frame.size;
    tester.platformDispatcher.textScaleFactorTestValue = frame.scale;
    tester.platformDispatcher.platformBrightnessTestValue = frame.brightness;
    await tester.pumpWidget(const SizedBox.shrink());
    final Future<void> Function()? restore = prepare;
    if (restore != null) {
      var prepared = false;
      final Future<void> pending = restore().whenComplete(() {
        prepared = true;
      });
      for (var attempt = 0; attempt < 40 && !prepared; attempt++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
      }
      await pending.timeout(const Duration(seconds: 5));
    }
    await pump(frame.brightness);
    await tester.pump(const Duration(milliseconds: 50));
    if (tall || scrollToSentence) {
      for (
        var attempt = 0;
        attempt < 30 && find.text(sentence).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
      }
    }
    if (scrollToSentence) {
      for (
        var attempt = 0;
        attempt < 30 && find.byType(Scrollable).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
      }
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
    }
    expect(find.text(sentence), findsOneWidget);
    if (expectBack) {
      expect(find.text('Back'), findsOneWidget);
    }
    if (tryAgain) {
      expect(find.text('Try again'), findsOneWidget);
    }
    final RenderRepaintBoundary boundary = tester
        .renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
    final ui.Image image = boundary.toImageSync(pixelRatio: 1);
    final ByteData? data = await tester.runAsync<ByteData?>(
      () => image
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(const Duration(seconds: 5)),
    );
    image.dispose();
    expect(data, isNotNull);
    final Directory directory = Directory(_evidenceDirectory);
    directory.createSync(recursive: true);
    File('${directory.path}${Platform.pathSeparator}$name-${frame.suffix}.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
    if (scrollToSentence) {
      tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
      await tester.pump();
    }
  }
}

class _ReadyUnlock implements PhoneUnlock {
  @override
  Future<PhoneUnlockSupport> isDeviceSupported() async {
    return PhoneUnlockSupport.ready;
  }

  @override
  Future<PhoneUnlockDecision> authenticate() async {
    return PhoneUnlockDecision.confirmed;
  }
}

class _CaptureStore extends ProfileStore {
  _CaptureStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  LocalRemoval? scriptedRemoval;

  @override
  Future<LocalRemoval> removeSubjectDirectoryFirst(String subjectId) {
    final LocalRemoval? scripted = scriptedRemoval;
    if (scripted != null) {
      return Future<LocalRemoval>.value(scripted);
    }
    return super.removeSubjectDirectoryFirst(subjectId);
  }
}
