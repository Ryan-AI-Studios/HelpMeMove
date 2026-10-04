import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/screens/focused_flow_screen.dart';
import 'package:helpmemove/design/screens/foundations_screen.dart';
import 'package:helpmemove/design/screens/home_screen.dart';
import 'package:helpmemove/design/screens/key_loss_screen.dart';
import 'package:helpmemove/design/screens/not_found_screen.dart';
import 'package:helpmemove/design/screens/storage_failure_screen.dart';
import 'package:helpmemove/design/shell/app_shell.dart';

class StorageRecovery {
  const StorageRecovery({required this.onRetry, required this.onReset});

  final Future<String> Function() onRetry;
  final Future<String> Function() onReset;
}

GoRouter buildHelpMeMoveRouter({
  String initialLocation = '/',
  StorageRecovery? recovery,
}) {
  final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: false,
    initialLocation: initialLocation,
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
              GoRoute(
                path: 'storage-failure',
                parentNavigatorKey: rootNavigatorKey,
                builder: (BuildContext context, GoRouterState state) {
                  return StorageFailureScreen(
                    onRetry: recovery == null
                        ? null
                        : () {
                            _follow(context, recovery.onRetry);
                          },
                  );
                },
              ),
              GoRoute(
                path: 'key-loss',
                parentNavigatorKey: rootNavigatorKey,
                builder: (BuildContext context, GoRouterState state) {
                  return KeyLossScreen(
                    onRetry: recovery == null
                        ? null
                        : () {
                            _follow(context, recovery.onRetry);
                          },
                    onReset: recovery == null
                        ? null
                        : () {
                            _follow(context, recovery.onReset);
                          },
                  );
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

void _follow(BuildContext context, Future<String> Function() action) {
  unawaited(
    action().then((String next) {
      if (!context.mounted) {
        return;
      }
      if (GoRouterState.of(context).uri.path != next) {
        context.go(next);
      }
    }),
  );
}
