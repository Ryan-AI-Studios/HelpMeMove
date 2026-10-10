import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/coach/explain_screen.dart';
import 'package:helpmemove/design/app_theme.dart';

import '../design/pump_app.dart';

void main() {
  testWidgets('Foundations opens explain and Home has no explain control', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Explain a selection'), findsNothing);
    expect(find.byType(ExplainScreen), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Foundations'));
    await pumpPastNavigation(tester);

    expect(
      find.text('Later destinations: Move, Progress, Coach, You.'),
      findsOneWidget,
    );
    expect(find.text('Explain a selection'), findsOneWidget);
    await tester.ensureVisible(find.text('Explain a selection'));
    await tester.tap(find.text('Explain a selection'));
    await tester.pumpAndSettle();

    expect(find.byType(ExplainScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Head and neck'), findsOneWidget);
    expect(find.text('Shoulder'), findsOneWidget);
    expect(find.text('Arm'), findsOneWidget);
    expect(find.text('Torso'), findsOneWidget);
    expect(find.text('Pelvis'), findsOneWidget);
    expect(find.text('Leg'), findsOneWidget);
    expect(find.text('Foot'), findsOneWidget);
    expect(find.text('Strength'), findsOneWidget);
    expect(find.text('Mobility'), findsOneWidget);
    expect(find.text('Stability'), findsOneWidget);
    expect(find.text('Conditioning'), findsOneWidget);
    expect(find.text('Control'), findsOneWidget);
  });

  test('explain screen does not write a profile or a workout', () {
    final String source = File('lib/coach/explain_screen.dart')
        .readAsStringSync();
    expect(source.contains('ProfileStore'), isFalse);
    expect(source.contains('TextField'), isFalse);
    expect(source.contains('speech_to_text'), isFalse);
    expect(source.contains('package:dio/'), isFalse);
    expect(source.contains('package:http/'), isFalse);
  });

  testWidgets('empty base stays on device and does not call the factory', (
    WidgetTester tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      ExplainScreen(
        apiBase: '',
        httpClientFactory: () {
          calls += 1;
          throw StateError('factory');
        },
      ),
    );

    expect(find.text('This note stays on this device.'), findsNothing);
    expect(find.text('Send'), findsNothing);
    await tester.tap(find.text('Shoulder'));
    await tester.pump();
    await tester.tap(find.text('Mobility'));
    await tester.pump();

    expect(find.text('This note stays on this device.'), findsOneWidget);
    expect(find.text('Send'), findsNothing);
    expect(find.textContaining('Ollama Cloud'), findsNothing);
    expect(calls, 0);
  });

  testWidgets('keep does not call the client factory', (
    WidgetTester tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      ExplainScreen(
        apiBase: 'http://127.0.0.1:8787',
        httpClientFactory: () {
          calls += 1;
          throw StateError('factory');
        },
      ),
    );

    await tester.tap(find.text('Shoulder'));
    await tester.pump();
    expect(
      find.text(
        'Send the selected area or focus to Ollama Cloud for an explanation? It does not send typed or spoken symptoms.',
      ),
      findsOneWidget,
    );
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Keep it on this device'), findsOneWidget);

    await tester.tap(find.text('Keep it on this device'));
    await tester.pump();

    expect(find.text('This note stays on this device.'), findsOneWidget);
    expect(find.text('Send'), findsNothing);
    expect(find.textContaining('Ollama Cloud'), findsNothing);
    expect(calls, 0);
  });

  test('the client posts only the two fields', () async {
    await HttpOverrides.runZoned(
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final Completer<String> bodyGate = Completer<String>();
        var method = '';
        var path = '';
        server.listen((HttpRequest request) async {
          method = request.method;
          path = request.uri.path;
          final String body = await utf8.decoder.bind(request).join();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType(
            'text',
            'plain',
            charset: 'utf-8',
          );
          request.response.write('Noted from the model.');
          await request.response.close();
          if (!bodyGate.isCompleted) {
            bodyGate.complete(body);
          }
        });
        final HttpClient client = HttpClient();
        try {
          final String text = await postExplainRequest(
            client,
            Uri.parse('http://127.0.0.1:${server.port}/coach/explain'),
            '{"selection_kind":"region","selection_id":"shoulder"}',
          );
          final String body = await bodyGate.future;
          expect(method, 'POST');
          expect(path, '/coach/explain');
          expect(body, '{"selection_kind":"region","selection_id":"shoulder"}');
          expect(text, 'Noted from the model.');
        } finally {
          client.close(force: true);
          await server.close(force: true);
        }
      },
      createHttpClient: (SecurityContext? context) {
        return _LiveHttpOverrides().createHttpClient(context);
      },
    );
  });

  testWidgets('send posts only the two fields', (WidgetTester tester) async {
    var calls = 0;
    HttpClient? client;
    String? jsonBody;
    Uri? uri;
    await _pump(
      tester,
      ExplainScreen(
        apiBase: 'http://127.0.0.1:8787',
        httpClientFactory: () {
          calls += 1;
          client = HttpClient();
          return client!;
        },
        poster: (HttpClient httpClient, Uri target, String body) async {
          jsonBody = body;
          uri = target;
          return '${'n' * 500}overflow';
        },
      ),
    );

    await tester.tap(find.text('Arm'));
    await tester.pump();
    await tester.ensureVisible(find.text('Strength'));
    await tester.tap(find.text('Strength'));
    await tester.pump();
    await tester.ensureVisible(find.text('Send'));
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump();

    expect(calls, 1);
    expect(client, isNotNull);
    expect(client!.connectionTimeout, const Duration(seconds: 15));
    expect(uri, Uri.parse('http://127.0.0.1:8787/coach/explain'));
    expect(jsonBody, '{"selection_kind":"focus","selection_id":"strength"}');
    final Object? parsed = jsonDecode(jsonBody!);
    expect(parsed, <String, Object?>{
      'selection_kind': 'focus',
      'selection_id': 'strength',
    });
    final Text reply = tester.widget<Text>(
      find.byKey(const Key('explain-reply')),
    );
    expect(reply.data, 'n' * 500);
    expect(
      find.text('This explanation is not a change to your plan.'),
      findsOneWidget,
    );
    expect(find.textContaining('overflow'), findsNothing);
  });

  testWidgets('a disposed route ignores a late body', (
    WidgetTester tester,
  ) async {
    final Completer<String> gate = Completer<String>();
    var calls = 0;
    await _pump(
      tester,
      ExplainScreen(
        apiBase: 'http://127.0.0.1:8787',
        httpClientFactory: () {
          calls += 1;
          return HttpClient();
        },
        poster: (HttpClient client, Uri uri, String jsonBody) {
          return gate.future;
        },
      ),
    );

    await tester.tap(find.text('Foot'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(calls, 1);

    GoRouter.of(tester.element(find.byType(ExplainScreen))).go('/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    gate.complete('late-body-marker');
    await tester.pump();

    expect(find.text('left-explain'), findsOneWidget);
    expect(find.textContaining('late-body-marker'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the request timeout is 15 seconds', (WidgetTester tester) async {
    final Completer<String> hung = Completer<String>();
    var calls = 0;
    await _pump(
      tester,
      ExplainScreen(
        apiBase: 'http://127.0.0.1:8787',
        httpClientFactory: () {
          calls += 1;
          return HttpClient();
        },
        poster: (HttpClient client, Uri uri, String jsonBody) {
          return hung.future;
        },
      ),
    );

    await tester.tap(find.text('Leg'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byKey(const Key('explain-reply')), findsNothing);

    await tester.pump(const Duration(seconds: 15));

    expect(find.text('Send'), findsOneWidget);
    expect(find.byKey(const Key('explain-reply')), findsNothing);
    expect(tester.takeException(), isNull);
    if (!hung.isCompleted) {
      hung.complete('too late for the route');
    }
    await tester.pump();
    expect(find.textContaining('too late'), findsNothing);
  });
}

class _LiveHttpOverrides extends HttpOverrides {
  @override
  // ignore: unnecessary_overrides
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

Future<void> _pump(WidgetTester tester, ExplainScreen screen) async {
  final GoRouter router = GoRouter(
    initialLocation: '/focus/explain',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) {
          return const Scaffold(body: Text('left-explain'));
        },
      ),
      GoRoute(
        path: '/focus/explain',
        builder: (BuildContext context, GoRouterState state) {
          return screen;
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.light,
      routerConfig: router,
    ),
  );
  await tester.pump();
}
