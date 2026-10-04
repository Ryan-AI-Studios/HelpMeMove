import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/tertiary_button.dart';
import 'package:helpmemove/intake/intake_draft.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.store,
    this.readStore,
    this.storageBlocked = false,
    this.storageBlockedNow,
    this.storageAccess,
  });

  final ProfileStore? store;
  final ProfileStore? Function()? readStore;
  final bool storageBlocked;
  final bool Function()? storageBlockedNow;
  final Listenable? storageAccess;

  bool get blockedNow => storageBlockedNow?.call() ?? storageBlocked;

  ProfileStore? get liveStore => readStore?.call() ?? store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _scaffoldCompleted = false;
  String? _bridgeResult;
  bool _entryReady = false;
  bool _hasDraft = false;
  String _resumeStep = 'intent';
  GoRouter? _router;
  Listenable? _access;
  String? _lastPath;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _reloadIfOpen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final GoRouter router = GoRouter.of(context);
    if (!identical(_router, router)) {
      _router?.routerDelegate.removeListener(_onRoute);
      _router = router;
      _lastPath = _pathOrNull();
      router.routerDelegate.addListener(_onRoute);
    }
    if (!identical(_access, widget.storageAccess)) {
      _access?.removeListener(_onAccess);
      _access = widget.storageAccess;
      _access?.addListener(_onAccess);
    }
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.store != oldWidget.store ||
        widget.readStore != oldWidget.readStore ||
        widget.blockedNow != oldWidget.blockedNow) {
      _entryReady = false;
      _reloadIfOpen();
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRoute);
    _access?.removeListener(_onAccess);
    super.dispose();
  }

  void _onAccess() {
    if (!mounted) {
      return;
    }
    setState(() {
      _entryReady = false;
    });
    _reloadIfOpen();
  }

  void _onRoute() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final String? path = _pathOrNull();
      final bool returnedHome =
          path == '/' && _lastPath != null && _lastPath != '/';
      if (path != null) {
        _lastPath = path;
      }
      if (!returnedHome) {
        return;
      }
      if (_entryReady) {
        setState(() {
          _entryReady = false;
        });
      }
      _reloadIfOpen();
    });
  }

  String? _pathOrNull() {
    final GoRouter? router = _router;
    if (router == null) {
      return null;
    }
    try {
      return router.state.uri.path;
    } on StateError {
      return null;
    }
  }

  void _reloadIfOpen() {
    final ProfileStore? store = widget.liveStore;
    if (store == null || widget.blockedNow) {
      return;
    }
    unawaited(_loadDraft(store));
  }

  Future<void> _loadDraft(ProfileStore store) async {
    final int generation = ++_loadGeneration;
    var hasDraft = false;
    var step = 'intent';
    try {
      final String? raw = await store.loadDraft();
      if (raw != null) {
        final LocalIntakeDraft draft = LocalIntakeDraft.decode(raw);
        hasDraft = true;
        step = draft.step;
      }
    } catch (_) {
      hasDraft = false;
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    setState(() {
      _entryReady = true;
      _hasDraft = hasDraft;
      _resumeStep = step;
    });
  }

  void _runBridgeCheck() {
    try {
      final String subject = acceptSubject(raw: 'subject-smoke-1');
      setState(() {
        _bridgeResult = subject == 'subject-smoke-1'
            ? 'Bridge check completed'
            : 'Bridge check failed';
      });
    } on BridgeError {
      setState(() {
        _bridgeResult = 'Bridge check failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? bridgeResult = _bridgeResult;
    final AppColors colors = appColorsOf(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.divider)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space8,
                  vertical: AppSpacing.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.space8,
                        vertical: AppSpacing.space8,
                      ),
                      child: Text('HelpMeMove'),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TertiaryButton(
                        label: 'Foundations',
                        onPressed: () => context.go('/foundations'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space20),
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.liveStore != null &&
                              !widget.blockedNow &&
                              _entryReady) ...[
                            PrimaryButton(
                              label: _hasDraft
                                  ? 'Continue intake'
                                  : 'Describe a limit',
                              onPressed: () {
                                final String step = _hasDraft
                                    ? _resumeStep
                                    : 'intent';
                                context.go('/focus/intake?step=$step');
                              },
                            ),
                            const SizedBox(height: AppSpacing.space24),
                          ],
                          PrimaryButton(
                            label: 'Scaffold check',
                            onPressed: () {
                              setState(() {
                                _scaffoldCompleted = true;
                              });
                            },
                          ),
                          if (_scaffoldCompleted) ...[
                            const SizedBox(height: AppSpacing.space24),
                            const Text(
                              'Scaffold check completed',
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.space24),
                          PrimaryButton(
                            label: 'Bridge check',
                            onPressed: _runBridgeCheck,
                          ),
                          if (bridgeResult != null) ...[
                            const SizedBox(height: AppSpacing.space24),
                            Text(bridgeResult, textAlign: TextAlign.center),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
