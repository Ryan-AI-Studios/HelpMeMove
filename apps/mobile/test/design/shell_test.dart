import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/screens/home_screen.dart';

import 'pump_app.dart';

void main() {
  testWidgets('compact width shows one bar and no rail', (tester) async {
    await pumpApp(tester, size: const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Move'), findsNothing);
  });

  testWidgets('expanded width shows one rail and no bar', (tester) async {
    await pumpApp(tester, size: const Size(840, 1200));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Move'), findsNothing);
  });

  testWidgets('focused flow hides navigation and back returns home', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Foundations'));
    await pumpPastNavigation(tester);
    await tester.ensureVisible(find.text('Focused flow'));
    await tester.tap(find.text('Focused flow'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Focused flow'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Scaffold check'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('unknown location shows only the not-found sentence', (
    tester,
  ) async {
    await pumpApp(tester);
    GoRouter.of(tester.element(find.byType(HomeScreen))).go('/not-listed');
    await tester.pumpAndSettle();

    expect(find.text('That page is not available.'), findsOneWidget);
    expect(find.textContaining('not-listed'), findsNothing);
    expect(find.byType(Text), findsOneWidget);
    expect(
      tester.widget<Text>(find.byType(Text)).data,
      'That page is not available.',
    );
  });

  testWidgets('text scale 2 keeps bridge check reachable', (tester) async {
    await pumpApp(tester, textScale: 2);
    await tester.scrollUntilVisible(
      find.text('Bridge check'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Bridge check'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
