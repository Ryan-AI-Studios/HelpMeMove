import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/shell/app_shell.dart';
import 'package:helpmemove/design/screens/focused_flow_screen.dart';
import 'package:helpmemove/design/screens/foundations_screen.dart';
import 'package:helpmemove/design/screens/home_screen.dart';
import 'package:helpmemove/design/screens/not_found_screen.dart';

GoRouter buildHelpMeMoveRouter() {
  final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: false,
    initialLocation: '/',
    errorBuilder: (BuildContext context, GoRouterState state) {
      return const NotFoundScreen();
    },
    routes: [
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return AppShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) {
              return const HomeScreen();
            },
            routes: [
              GoRoute(
                path: 'focus',
                parentNavigatorKey: rootNavigatorKey,
                builder: (BuildContext context, GoRouterState state) {
                  return const FocusedFlowScreen();
                },
              ),
            ],
          ),
          GoRoute(
            path: '/foundations',
            builder: (BuildContext context, GoRouterState state) {
              return const FoundationsScreen();
            },
          ),
        ],
      ),
    ],
  );
}
