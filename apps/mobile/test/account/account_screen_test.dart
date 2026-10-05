import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/account/account_controller.dart';
import 'package:helpmemove/account/account_screen.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/main.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';

const String _evidenceDirectory =
    r'C:\dev\HelpMeMove\conductor\0019-AuthenticationAndAccountIsolation\ui-evidence';

bool _captureFontReady = false;

ThemeData _platformFont(ThemeData theme) {
  if (!_captureFontReady) {
    return theme;
  }
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Segoe UI'),
  );
}

const String _hidden = 'Earlier program session report';
const String _actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
    TestWidgetsFlutterBinding.ensureInitialized();
    final List<File> fonts = <File>[
      File(r'C:\Windows\Fonts\segoeui.ttf'),
      File(r'C:\Windows\Fonts\segoeuib.ttf'),
    ];
    if (fonts.any((File file) => !file.existsSync())) {
      return;
    }
    final FontLoader loader = FontLoader('Segoe UI');
    for (final File file in fonts) {
      final Uint8List bytes = await file.readAsBytes();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
    _captureFontReady = true;
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-account-ui');
  });

  tearDown(() async {
    await live?.close();
    live = null;
    if (temp.existsSync()) {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // A database file can stay locked if a widget future is still closing.
      }
    }
  });

  ProfileStore openStore() {
    final ProfileStore store = ProfileStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 5),
      random: Random(7),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    return store;
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    required Brightness brightness,
    AccountController? controller,
    bool unavailable = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: _platformFont(AppTheme.light()),
        darkTheme: _platformFont(AppTheme.dark()),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        themeAnimationDuration: Duration.zero,
        home: AccountScreen(controller: controller, unavailable: unavailable),
      ),
    );
    // Material animates DefaultTextStyle for kThemeChangeDuration. One frame
    // still shows the previous palette, so settle before the capture.
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      brightness,
    );
    final AppColors colors = brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
    final Iterable<RenderParagraph> paragraphs = tester
        .renderObjectList<RenderParagraph>(find.byType(Text));
    final bool bodyIsReadable = paragraphs.any(
      (RenderParagraph paragraph) =>
          paragraph.text.style?.color == colors.textPrimary,
    );
    final bool buttonsOnly = paragraphs.every(
      (RenderParagraph paragraph) =>
          paragraph.text.style?.color == colors.onAccent,
    );
    expect(bodyIsReadable || buttonsOnly, isTrue);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final RenderRepaintBoundary boundary = tester
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('account-capture')),
        );
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    final ByteData? data = await tester.runAsync<ByteData?>(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    image.dispose();
    expect(data, isNotNull);
    if (!_captureFontReady) {
      return;
    }
    final File file = File(
      '$_evidenceDirectory${Platform.pathSeparator}$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  }

  testWidgets('a widget test can open a profile', (tester) async {
    final ProfileStore store = openStore();
    final String? subject = await tester.runAsync(store.createProfile);
    expect(subject, isNotNull);
    expect(store.activeSubjectId, subject);
  });

  testWidgets('every account state renders at the required sizes and themes', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    final AccountController account = AccountController(store: store);
    final List<
      ({
        String name,
        String? sentence,
        List<String> buttons,
        void Function(AccountController account) prepare,
      })
    >
    states =
        <
          ({
            String name,
            String? sentence,
            List<String> buttons,
            void Function(AccountController account) prepare,
          })
        >[
          (
            name: 'signed-out',
            sentence: 'An account is optional. Workouts on this device stay on this device.',
            buttons: <String>['Stay on this device', 'Use this sign-in'],
            prepare: (AccountController account) {
              account.actorId = _actor;
              account.phase = AccountPhase.signedOut;
            },
          ),
          (
            name: 'confirm-bind',
            sentence: 'Use this sign-in with the profile already on this device? Nothing is uploaded.',
            buttons: <String>['Use this sign-in', 'Not now'],
            prepare: (AccountController account) {
              account.actorId = _actor;
              account.phase = AccountPhase.confirmBind;
            },
          ),
          (
            name: 'signed-in',
            sentence: 'Signed in on this device.',
            buttons: <String>['Sign out'],
            prepare: (AccountController account) {
              account.actorId = _actor;
              account.phase = AccountPhase.signedIn;
            },
          ),
          (
            name: 'sign-out',
            sentence: null,
            buttons: <String>[
              'Keep a locked copy on this device',
              'Remove the copy on this device',
            ],
            prepare: (AccountController account) {
              account.phase = AccountPhase.signOutChoice;
            },
          ),
          (
            name: 'switching',
            sentence: 'Opening the other profile.',
            buttons: <String>[],
            prepare: (AccountController account) {
              account.phase = AccountPhase.switching;
            },
          ),
          (
            name: 'expired',
            sentence:
                'This sign-in expired. Workouts on this device stay here.',
            buttons: <String>[],
            prepare: (AccountController account) {
              account.phase = AccountPhase.expired;
            },
          ),
          (
            name: 'access-removed',
            sentence: 'This sign-in cannot be used. Workouts on this device stay here.',
            buttons: <String>[],
            prepare: (AccountController account) {
              account.phase = AccountPhase.accessRemoved;
            },
          ),
          (
            name: 'reauth',
            sentence: 'Confirm this sign-in to continue.',
            buttons: <String>['Confirm', 'Cancel'],
            prepare: (AccountController account) {
              account.actorId = _actor;
              account.phase = AccountPhase.reauth;
            },
          ),
        ];
    const List<({String name, Size size, double scale, Brightness brightness})>
    viewports =
        <({String name, Size size, double scale, Brightness brightness})>[
          (
            name: 'light-390-t1',
            size: Size(390, 844),
            scale: 1,
            brightness: Brightness.light,
          ),
          (
            name: 'dark-390-t1',
            size: Size(390, 844),
            scale: 1,
            brightness: Brightness.dark,
          ),
          (
            name: 'light-840-t1',
            size: Size(840, 900),
            scale: 1,
            brightness: Brightness.light,
          ),
          (
            name: 'light-390-t2',
            size: Size(390, 844),
            scale: 2,
            brightness: Brightness.light,
          ),
        ];

    for (final ({String name, Size size, double scale, Brightness brightness})
        viewport
        in viewports) {
      for (final state in states) {
        account.previousMarker = _hidden;
        state.prepare(account);
        account.notifyListeners();
        await pumpScreen(
          tester,
          size: viewport.size,
          textScale: viewport.scale,
          brightness: viewport.brightness,
          controller: account,
        );
        if (state.sentence != null) {
          expect(find.text(state.sentence!), findsOneWidget);
        }
        expect(find.byType(PrimaryButton), findsNWidgets(state.buttons.length));
        for (final String label in state.buttons) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text(_hidden), findsNothing);
        expect(find.text(_actor), findsNothing);
        expect(find.text('a@example.test'), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(NavigationRail), findsNothing);
        expect(tester.takeException(), isNull);
        await capture(tester, 'account-${state.name}-${viewport.name}');
      }

      await pumpScreen(
        tester,
        size: viewport.size,
        textScale: viewport.scale,
        brightness: viewport.brightness,
        unavailable: true,
      );
      expect(find.text('That page is unavailable.'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsNothing);
      expect(find.text('secret-token'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, 'account-unavailable-${viewport.name}');
    }

    account.actorId = null;
    account.phase = AccountPhase.signedOut;
    account.notifyListeners();
    await pumpScreen(
      tester,
      size: const Size(390, 844),
      textScale: 1,
      brightness: Brightness.light,
      controller: account,
    );
    expect(find.text('Use this sign-in'), findsNothing);
    expect(find.text('Stay on this device'), findsOneWidget);
  });

  testWidgets('the account controls bind, decline, sign out, and confirm', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    final String first =
        await tester.runAsync(store.createProfile) ??
        (throw StateError('profile'));
    final String second =
        await tester.runAsync(store.createProfile) ??
        (throw StateError('profile'));
    await tester.runAsync(() => store.switchTo(first));
    final AccountController account = AccountController(store: store);
    await tester.runAsync(() => account.presentActor(_actor));
    const Size size = Size(390, 844);
    await pumpScreen(
      tester,
      size: size,
      textScale: 1,
      brightness: Brightness.light,
      controller: account,
    );

    await tester.tap(find.text('Use this sign-in'));
    await tester.pump();
    expect(
      find.text(
        'Use this sign-in with the profile already on this device? Nothing is uploaded.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(await store.keys.read(AccountController.actorItem(_actor)), isNull);
    expect(
      find.text(
        'An account is optional. Workouts on this device stay on this device.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Use this sign-in'));
    await tester.pump();
    await _press(tester, 'Use this sign-in');
    expect(find.text('Signed in on this device.'), findsOneWidget);
    expect(await store.keys.read(AccountController.actorItem(_actor)), first);

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(find.text('Keep a locked copy on this device'), findsOneWidget);
    expect(find.text('Remove the copy on this device'), findsOneWidget);
    await _press(tester, 'Keep a locked copy on this device');
    expect(account.phase, AccountPhase.signedOut);
    expect(store.activeSubjectId, isNull);
    expect(await store.keys.read(AccountController.actorItem(_actor)), first);
    expect(
      find.text(
        'An account is optional. Workouts on this device stay on this device.',
      ),
      findsOneWidget,
    );

    await tester.runAsync(() => store.switchTo(first));
    account.actorId = _actor;
    account.phase = AccountPhase.signedIn;
    account.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await _press(tester, 'Remove the copy on this device');
    expect(account.phase, AccountPhase.signedOut);
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles${Platform.pathSeparator}$first',
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles${Platform.pathSeparator}$second',
      ).existsSync(),
      isTrue,
    );

    var ran = false;
    account.actorId = _actor;
    account.requestReauth(() {
      ran = true;
    });
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(ran, isFalse);
    account.requestReauth(() {
      ran = true;
    });
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(ran, isTrue);
  });

  testWidgets('home opens account outside the shell and blocks token links', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    final String subject =
        await tester.runAsync(store.createProfile) ??
        (throw StateError('profile'));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await _until(tester, find.text('Account'));
    expect(
      tester.getTopLeft(find.text('Account')).dy,
      greaterThan(tester.getTopLeft(find.text('Report a problem')).dy),
    );
    await tester.ensureVisible(find.text('Account'));
    await tester.tap(find.text('Account'));
    await _until(
      tester,
      find.text(
        'An account is optional. Workouts on this device stay on this device.',
      ),
    );
    expect(
      find.text(
        'An account is optional. Workouts on this device stay on this device.',
      ),
      findsOneWidget,
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.text('Stay on this device'));
    await _until(tester, find.text('HelpMeMove'));
    expect(find.text('HelpMeMove'), findsOneWidget);

    await tester.pumpWidget(
      HelpMeMoveApp(
        key: UniqueKey(),
        store: store,
        initialLocation: '/focus/account?token=secret-token',
      ),
    );
    await tester.pump();
    expect(find.text('That page is unavailable.'), findsOneWidget);
    expect(find.text('secret-token'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(store.activeSubjectId, subject);

    await tester.pumpWidget(
      HelpMeMoveApp(
        key: UniqueKey(),
        store: store,
        initialLocation: '/focus/account?email=a@example.test',
      ),
    );
    await tester.pump();
    expect(find.text('That page is unavailable.'), findsOneWidget);
    expect(find.text('a@example.test'), findsNothing);
    expect(store.activeSubjectId, subject);

    await tester.pumpWidget(
      HelpMeMoveApp(
        key: UniqueKey(),
        store: store,
        initialLocation: '/focus/account?session=abc',
      ),
    );
    await tester.pump();
    expect(find.text('That page is unavailable.'), findsOneWidget);
    expect(find.text('abc'), findsNothing);
    expect(store.activeSubjectId, subject);
  });
}

Future<void> _press(WidgetTester tester, String label) async {
  final PrimaryButton button = tester.widget<PrimaryButton>(
    find.widgetWithText(PrimaryButton, label),
  );
  final VoidCallback? onPressed = button.onPressed;
  expect(onPressed, isNotNull);
  await tester.runAsync(() async {
    onPressed!.call();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    if (finder.evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
  }
  expect(finder, findsOneWidget);
}
