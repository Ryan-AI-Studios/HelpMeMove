import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/account/account_controller.dart';
import 'package:helpmemove/account/account_screen.dart';
import 'package:helpmemove/account/phone_unlock.dart';
import 'package:helpmemove/design/screens/focused_flow_screen.dart';
import 'package:helpmemove/design/screens/foundations_screen.dart';
import 'package:helpmemove/design/screens/home_screen.dart';
import 'package:helpmemove/design/screens/key_loss_screen.dart';
import 'package:helpmemove/design/screens/not_found_screen.dart';
import 'package:helpmemove/design/screens/storage_failure_screen.dart';
import 'package:helpmemove/assessment/assessment_flow.dart';
import 'package:helpmemove/design/shell/app_shell.dart';
import 'package:helpmemove/intake/intake_flow.dart';
import 'package:helpmemove/privacy/privacy_screen.dart';
import 'package:helpmemove/report/report_screen.dart';
import 'package:helpmemove/program/program_document.dart';
import 'package:helpmemove/program/program_flow.dart';
import 'package:helpmemove/progress/progress_screen.dart';
import 'package:helpmemove/readiness/flare_followup_flow.dart';
import 'package:helpmemove/readiness/modified_plan_screen.dart';
import 'package:helpmemove/readiness/readiness_flow.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/workout/camera_preview_host.dart';
import 'package:helpmemove/workout/workout_flow.dart';

class StorageRecovery {
  const StorageRecovery({required this.onRetry, required this.onReset});

  final Future<String> Function() onRetry;
  final Future<String> Function() onReset;
}

/// Recovery can clear this after the app has already started on a failure route.
/// Starts false for each router. A query parameter cannot open it.
class _MovementGate {
  bool open = false;

  void allow() {
    open = true;
  }
}

class _IntakeAccess extends ChangeNotifier {
  _IntakeAccess({required this._blocked});

  bool _blocked;

  bool get blocked => _blocked;

  set blocked(bool value) {
    if (_blocked == value) {
      return;
    }
    _blocked = value;
    notifyListeners();
  }
}

GoRouter buildHelpMeMoveRouter({
  String initialLocation = '/',
  StorageRecovery? recovery,
  ProfileStore? store,
  ProfileStore? Function()? readStore,
  bool storageBlocked = false,
  SafetyView? previewSafetyView,
  LocalProgram? previewProgram,
  String? previewSession,
  String? previewAdaptation,
  bool movementGateOpen = false,
  void Function(String choice)? onAppearanceSaved,
  PhoneUnlock? phoneUnlock,
}) {
  final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();
  final _IntakeAccess access = _IntakeAccess(blocked: storageBlocked);
  final _MovementGate movement = _MovementGate();
  if (movementGateOpen) {
    movement.open = true;
  }
  AccountController? accountController;
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
              return HomeScreen(
                store: store,
                readStore: () => readStore?.call() ?? store,
                storageBlocked: access.blocked,
                storageBlockedNow: () => access.blocked,
                storageAccess: access,
              );
            },
            routes: [
              GoRoute(
                path: 'focus',
                parentNavigatorKey: rootNavigatorKey,
                builder: (BuildContext context, GoRouterState state) {
                  return const FocusedFlowScreen();
                },
                routes: [
                  GoRoute(
                    path: 'intake',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final ProfileStore? profile = readStore?.call() ?? store;
                      final String step =
                          state.uri.queryParameters['step'] ?? 'intent';
                      if (profile == null || access.blocked) {
                        return const IntakeUnavailable();
                      }
                      return IntakeFlow(
                        store: profile,
                        initialStep: step,
                        holdCheck: state.uri.queryParameters['hold'] == '1',
                        onContinue: () {
                          movement.allow();
                          context.go('/focus/assessment?step=intro');
                        },
                        previewSafetyView: previewSafetyView,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'assessment',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (!movement.open) {
                        return const AssessmentBlocked();
                      }
                      if (profile == null || access.blocked) {
                        return const AssessmentUnavailable();
                      }
                      final String step =
                          state.uri.queryParameters['step'] ?? 'intro';
                      return AssessmentFlow(
                        store: profile,
                        initialStep: step,
                        planAllowed: movement.open,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'program',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      if (!movement.open) {
                        return const ProgramBlocked();
                      }
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (profile == null || access.blocked) {
                        return const ProgramUnavailable();
                      }
                      return ProgramFlow(
                        store: profile,
                        preview: previewProgram,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'camera-guidance',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (profile == null || access.blocked) {
                        return const WorkoutUnavailable();
                      }
                      return CameraGuidanceRoute(
                        onLeave: () => context.go('/focus/workout'),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'workout',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (profile == null || access.blocked) {
                        return const WorkoutUnavailable();
                      }
                      return WorkoutFlow(
                        store: profile,
                        previewDocument: previewSession,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'readiness',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (profile == null || access.blocked) {
                        return const WorkoutUnavailable();
                      }
                      return ReadinessFlow(store: profile);
                    },
                  ),
                  GoRoute(
                    path: 'flare-followup',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (profile == null || access.blocked) {
                        return const WorkoutUnavailable();
                      }
                      return FlareFollowupFlow(store: profile);
                    },
                  ),
                  GoRoute(
                    path: 'progress',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (profile == null || access.blocked) {
                        return const WorkoutUnavailable();
                      }
                      return ProgressScreen(store: profile);
                    },
                  ),
                  GoRoute(
                    path: 'privacy',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (profile == null || access.blocked) {
                        return const WorkoutUnavailable();
                      }
                      accountController ??= AccountController(
                        store: profile,
                        phoneUnlock: phoneUnlock,
                      );
                      return PrivacyScreen(
                        store: profile,
                        onAppearanceSaved: onAppearanceSaved,
                        controller: accountController,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'account',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      if (accountLinkIsUnavailable(state.uri)) {
                        return const AccountScreen(unavailable: true);
                      }
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (profile == null || access.blocked) {
                        accountController?.closeAccountRoute();
                        return const WorkoutUnavailable();
                      }
                      accountController ??= AccountController(
                        store: profile,
                        phoneUnlock: phoneUnlock,
                      );
                      return AccountScreen(controller: accountController);
                    },
                  ),
                  GoRoute(
                    path: 'report',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (profile == null || access.blocked) {
                        return const WorkoutUnavailable();
                      }
                      return ReportScreen(
                        store: profile,
                        sessionId: state.uri.queryParameters['session'],
                      );
                    },
                  ),
                  GoRoute(
                    path: 'modified-plan',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final ProfileStore? profile = readStore?.call() ?? store;
                      if (profile == null || access.blocked) {
                        return const WorkoutUnavailable();
                      }
                      return ModifiedPlanScreen(
                        store: profile,
                        previewDocument: previewAdaptation,
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'storage-failure',
                parentNavigatorKey: rootNavigatorKey,
                builder: (BuildContext context, GoRouterState state) {
                  return StorageFailureScreen(
                    onRetry: recovery == null
                        ? null
                        : () {
                            _follow(context, recovery.onRetry, access);
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
                            _follow(context, recovery.onRetry, access);
                          },
                    onReset: recovery == null
                        ? null
                        : () {
                            _follow(context, recovery.onReset, access);
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

void _follow(
  BuildContext context,
  Future<String> Function() action,
  _IntakeAccess access,
) {
  final GoRouter router = GoRouter.of(context);
  unawaited(
    action().then((String next) {
      access.blocked = next != '/';
      if (router.state.uri.path != next) {
        router.go(next);
      }
    }),
  );
}
