import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/tertiary_button.dart';
import 'package:helpmemove/intake/intake_draft.dart';
import 'package:helpmemove/program/program_document.dart';
import 'package:helpmemove/readiness/adaptation_document.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/workout/session_document.dart';

class _MoveChoice {
  const _MoveChoice({
    this.workout = '',
    this.checkIn = false,
    this.flareCheckIn = false,
    this.notice = '',
    this.clearedCheck = false,
  });

  final String workout;
  final bool checkIn;
  final bool flareCheckIn;
  final String notice;
  final bool clearedCheck;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.store,
    this.readStore,
    this.storageBlocked = false,
    this.storageBlockedNow,
    this.storageAccess,
    this.recalledDocuments,
    this.disableListJson,
  });

  final ProfileStore? store;
  final ProfileStore? Function()? readStore;
  final bool storageBlocked;
  final bool Function()? storageBlockedNow;
  final Listenable? storageAccess;
  final List<String>? recalledDocuments;
  final String? disableListJson;

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
  String _workout = '';
  bool _clearedDraft = false;
  bool _showCheckIn = false;
  bool _showFlareCheckIn = false;
  bool _clearedCheck = false;
  String _moveNotice = '';
  String _recallNotice = '';
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
    if (widget.blockedNow) {
      return;
    }
    final ProfileStore? store = widget.liveStore;
    if (store == null && widget.recalledDocuments == null) {
      return;
    }
    unawaited(_loadDraft(store));
  }

  Future<void> _loadDraft(ProfileStore? store) async {
    final int generation = ++_loadGeneration;
    var hasDraft = false;
    var step = 'intent';
    if (store == null) {
      final String recall = _recallFromSeam();
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _entryReady = true;
        _recallNotice = recall;
      });
      return;
    }
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
    var workout = '';
    var cleared = false;
    var checkIn = false;
    var flareCheckIn = false;
    var clearedCheck = false;
    var notice = '';
    try {
      final String? raw = await store.loadWorkoutDraft();
      if (raw != null) {
        try {
          LocalSession.decode(raw);
          workout = 'resume';
        } on LocalSessionException {
          await store.deleteWorkoutDraft();
          cleared = true;
        }
      }
    } catch (_) {
      workout = '';
      cleared = false;
    }
    if (workout.isEmpty) {
      var programReady = false;
      try {
        final String? raw = await store.loadProgramRecord();
        if (raw != null) {
          LocalProgram.decode(raw);
          programReady = true;
        }
      } catch (_) {
        programReady = false;
      }
      if (programReady) {
        final _MoveChoice choice = await _moveChoice(store);
        workout = choice.workout;
        checkIn = choice.checkIn;
        flareCheckIn = choice.flareCheckIn;
        clearedCheck = choice.clearedCheck;
        notice = choice.notice;
      }
    }
    final String recall = await _recallNoticeFor(store);
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    setState(() {
      _entryReady = true;
      _hasDraft = hasDraft;
      _resumeStep = step;
      _workout = workout;
      _clearedDraft = cleared;
      _showCheckIn = checkIn;
      _showFlareCheckIn = flareCheckIn;
      _clearedCheck = clearedCheck;
      _moveNotice = notice;
      _recallNotice = recall;
    });
  }

  String _recallFromSeam() {
    try {
      final List<String> documents =
          widget.recalledDocuments ?? const <String>[];
      final List<String> ids = recalledSessions(
        documents: documents,
        disableListJson: widget.disableListJson ?? '',
      );
      if (ids.isEmpty) {
        return '';
      }
      return 'A stored session used a recalled rule.';
    } catch (_) {
      return '';
    }
  }

  Future<String> _recallNoticeFor(ProfileStore store) async {
    try {
      if (widget.recalledDocuments != null) {
        return _recallFromSeam();
      }
      final String verified = verifyDisableList(
        json: committedDisableList(),
        signatureHex: committedDisableListSig(),
      );
      if (verified != 'accept') {
        return '';
      }
      final List<String> documents = await store.workoutRecordDocuments();
      final List<String> ids = recalledSessions(
        documents: documents,
        disableListJson: committedDisableList(),
      );
      if (ids.isEmpty) {
        return '';
      }
      return 'A stored session used a recalled rule.';
    } catch (_) {
      return '';
    }
  }

  Future<_MoveChoice> _moveChoice(ProfileStore store) async {
    final StoredTerminalWorkout? terminal;
    try {
      terminal = await store.loadNewestTerminalWorkout();
    } catch (_) {
      return const _MoveChoice(workout: 'start');
    }
    if (terminal == null) {
      return const _MoveChoice(workout: 'start');
    }
    final LocalSession session;
    try {
      session = LocalSession.decode(terminal.documentJson);
    } on LocalSessionException {
      return const _MoveChoice();
    }
    if (session.outcome == 'safety_stopped') {
      return const _MoveChoice(
        notice: 'The last session stopped. No change was saved.',
      );
    }
    if (session.outcome != 'completed' && session.outcome != 'abandoned') {
      return const _MoveChoice();
    }
    final String? readiness = await store.loadReadinessRecord(
      terminal.sessionId,
    );
    final String? adaptation = await store.loadAdaptationRecord(
      terminal.sessionId,
    );
    if (readiness != null && adaptation != null) {
      try {
        decodeReadiness(readiness, sessionId: terminal.sessionId);
        final StoredAdaptation decision = StoredAdaptation.decode(adaptation);
        if (decision.sessionId != terminal.sessionId) {
          throw const AdaptationDocumentException();
        }
        if (decision.action == 'pause_today') {
          return _MoveChoice(notice: decision.reason);
        }
        if (decision.action != 'maintain') {
          throw const AdaptationDocumentException();
        }
        return await _flareChoice(store, terminal.sessionId, decision.reason);
      } on AdaptationDocumentException {
        // The pair is replaced by the cleared notice below.
      }
    }
    if (readiness != null || adaptation != null) {
      await store.deleteAdaptationPair(terminal.sessionId);
      return const _MoveChoice(
        checkIn: true,
        notice: 'The saved check could not be read. It was cleared.',
      );
    }
    return const _MoveChoice(checkIn: true);
  }

  Future<_MoveChoice> _flareChoice(
    ProfileStore store,
    String sessionId,
    String readinessReason,
  ) async {
    final String? raw = await store.loadFlareFollowup(sessionId);
    if (raw == null) {
      return _MoveChoice(flareCheckIn: true, notice: readinessReason);
    }
    try {
      final StoredFlareFollowup followup = StoredFlareFollowup.decode(raw);
      if (followup.sessionId != sessionId) {
        throw const AdaptationDocumentException();
      }
      if (followup.action == 'keep_program') {
        return _MoveChoice(workout: 'start', notice: followup.reason);
      }
      if (followup.action == 'pause_today') {
        return _MoveChoice(notice: followup.reason);
      }
      throw const AdaptationDocumentException();
    } on AdaptationDocumentException {
      await store.deleteFlareFollowup(sessionId);
      return _MoveChoice(
        flareCheckIn: true,
        notice: readinessReason,
        clearedCheck: true,
      );
    }
  }

  bool get _showWithheld {
    try {
      final Map<String, String> query = GoRouterState.of(context)
          .uri
          .queryParameters;
      return query['adaptation'] == 'withheld' || query['flare'] == 'withheld';
    } catch (_) {
      return false;
    }
  }

  bool get _showCleared {
    if (_clearedDraft) {
      return true;
    }
    try {
      return GoRouterState.of(context).uri.queryParameters['workout'] ==
          'cleared';
    } catch (_) {
      return false;
    }
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
        child: RepaintBoundary(
          key: const Key('home-capture'),
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
                            if (_clearedCheck) ...[
                              const Text(
                                'The saved check could not be read. It was cleared.',
                              ),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            if (_recallNotice.isNotEmpty) ...[
                              Text(_recallNotice),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            if (_moveNotice.isNotEmpty) ...[
                              Text(_moveNotice),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            if (_showWithheld) ...[
                              const Text('No change was saved.'),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            if (widget.liveStore != null &&
                                !widget.blockedNow &&
                                _entryReady &&
                                _workout.isNotEmpty) ...[
                              PrimaryButton(
                                label: _workout == 'resume'
                                    ? 'Resume workout'
                                    : 'Start workout',
                                onPressed: () => context.go('/focus/workout'),
                              ),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            if (widget.liveStore != null &&
                                !widget.blockedNow &&
                                _entryReady &&
                                _showCheckIn) ...[
                              PrimaryButton(
                                label: 'How are you feeling today?',
                                onPressed: () => context.go('/focus/readiness'),
                              ),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            if (widget.liveStore != null &&
                                !widget.blockedNow &&
                                _entryReady &&
                                _showFlareCheckIn) ...[
                              PrimaryButton(
                                label: 'Check in on the last session',
                                onPressed: () =>
                                    context.go('/focus/flare-followup'),
                              ),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            if (_showCleared) ...[
                              const Text(
                                'The saved workout could not be read. It was cleared.',
                              ),
                              const SizedBox(height: AppSpacing.space24),
                            ],
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
                            if (widget.liveStore != null &&
                                !widget.blockedNow &&
                                _entryReady) ...[
                              PrimaryButton(
                                label: 'See local progress',
                                onPressed: () => context.go('/focus/progress'),
                              ),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            if (widget.liveStore != null &&
                                !widget.blockedNow &&
                                _entryReady) ...[
                              PrimaryButton(
                                label: 'Privacy and appearance',
                                onPressed: () => context.go('/focus/privacy'),
                              ),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            if (widget.liveStore != null &&
                                !widget.blockedNow &&
                                _entryReady) ...[
                              PrimaryButton(
                                label: 'Report a problem',
                                onPressed: () => context.go('/focus/report'),
                              ),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            if (widget.liveStore != null &&
                                !widget.blockedNow &&
                                _entryReady) ...[
                              PrimaryButton(
                                label: 'Account',
                                onPressed: () => context.go('/focus/account'),
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
      ),
    );
  }
}
