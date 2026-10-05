import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/secondary_button.dart';
import 'package:helpmemove/design/components/tertiary_button.dart';
import 'package:helpmemove/program/program_document.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/workout/session_document.dart';

/// Monotonic session clock. Production uses a stopwatch. Tests advance by hand.
abstract class WorkoutClock {
  int get elapsedMilliseconds;

  void start();

  void stop();

  void reset();
}

class StopwatchWorkoutClock implements WorkoutClock {
  final Stopwatch _watch = Stopwatch();

  @override
  int get elapsedMilliseconds => _watch.elapsedMilliseconds;

  @override
  void start() => _watch.start();

  @override
  void stop() => _watch.stop();

  @override
  void reset() => _watch.reset();
}

class ManualWorkoutClock implements WorkoutClock {
  @override
  int elapsedMilliseconds = 0;

  bool _running = false;

  @override
  void start() {
    _running = true;
  }

  @override
  void stop() {
    _running = false;
  }

  @override
  void reset() {
    elapsedMilliseconds = 0;
    _running = false;
  }

  void advance(int milliseconds) {
    if (_running && milliseconds > 0) {
      elapsedMilliseconds += milliseconds;
    }
  }
}

/// No profile. Home only. No open and no write.
class WorkoutUnavailable extends StatelessWidget {
  const WorkoutUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: Center(
            child: PrimaryButton(
              label: 'Home',
              onPressed: () => context.go('/'),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkoutFlow extends StatefulWidget {
  const WorkoutFlow({super.key, this.store, this.previewDocument, this.clock});

  final ProfileStore? store;
  final String? previewDocument;
  final WorkoutClock? clock;

  @override
  State<WorkoutFlow> createState() => _WorkoutFlowState();
}

class _WorkoutFlowState extends State<WorkoutFlow> with WidgetsBindingObserver {
  late final WorkoutClock _clock = widget.clock ?? StopwatchWorkoutClock();
  final Map<String, ExerciseDisplay> _displays = <String, ExerciseDisplay>{};
  Timer? _restTimer;
  LocalSession? _session;
  String _documentJson = '';
  int _origin = 0;
  int _minutes = 15;
  bool _ready = false;
  bool _missing = false;
  bool _reporting = false;
  bool _applying = false;
  bool _pausePending = false;
  String _symptom = 'mild_discomfort';
  int _pain = 0;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final String? preview = widget.previewDocument;
    if (preview != null) {
      _adoptPreview(preview);
      return;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      return;
    }
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused) {
      return;
    }
    _clock.stop();
    final String? current = _session?.state;
    if (_applying || current == 'active' || current == 'resting') {
      _pausePending = true;
    }
    if (_reporting && (current == 'active' || current == 'resting')) {
      unawaited(_commitPain());
      return;
    }
    if (current == 'active' || current == 'resting') {
      unawaited(_apply('{"name":"pause"}'));
    }
  }

  void _adoptPreview(String raw) {
    try {
      final LocalSession session = LocalSession.decode(raw);
      _documentJson = raw;
      _session = session;
      _origin = session.monotonicMs;
      _clock.reset();
      _followClock(session);
      _ready = true;
    } catch (_) {
      _missing = true;
      _ready = true;
    }
  }

  Future<void> _load() async {
    final int generation = ++_loadGeneration;
    final ProfileStore? store = widget.store;
    if (store == null) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _missing = true;
        _ready = true;
      });
      return;
    }
    String? draft;
    try {
      draft = await store.loadWorkoutDraft();
    } catch (_) {
      _failStorage();
      return;
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    if (draft != null) {
      try {
        _showDecoded(LocalSession.decode(draft), draft);
        return;
      } catch (_) {
        try {
          await store.deleteWorkoutDraft();
        } catch (_) {
          _failStorage();
          return;
        }
        if (!mounted) {
          return;
        }
        context.go('/?workout=cleared');
        return;
      }
    }
    String? program;
    try {
      program = await store.loadProgramRecord();
    } catch (_) {
      _failStorage();
      return;
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    if (program == null) {
      setState(() {
        _missing = true;
        _ready = true;
      });
      return;
    }
    final LocalProgram? decoded = _decodeProgram(program);
    if (decoded == null) {
      setState(() {
        _missing = true;
        _ready = true;
      });
      return;
    }
    _minutes = decoded.sessionMinutes;
    _clock.reset();
    _clock.start();
    final int now = _clock.elapsedMilliseconds;
    final WorkoutView opened = openWorkout(
      programJson: program,
      monotonicMillis: now,
      sessionId: store.newSessionId(),
    );
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    if (opened.outcome != 'ready' || opened.documentJson.isEmpty) {
      _clock.stop();
      setState(() {
        _missing = true;
        _ready = true;
      });
      return;
    }
    try {
      final LocalSession session = LocalSession.decode(opened.documentJson);
      _documentJson = opened.documentJson;
      _session = session;
      _origin = now - _clock.elapsedMilliseconds;
      await store.saveWorkoutDraft(opened.documentJson);
    } catch (_) {
      _failStorage();
      return;
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    setState(() {
      _ready = true;
    });
    _followClock(_session!);
  }

  LocalProgram? _decodeProgram(String raw) {
    try {
      return LocalProgram.decode(raw);
    } catch (_) {
      return null;
    }
  }

  void _showDecoded(LocalSession session, String raw) {
    _documentJson = raw;
    _session = session;
    _origin = session.monotonicMs - _clock.elapsedMilliseconds;
    _followClock(session);
    setState(() {
      _ready = true;
    });
  }

  void _failStorage() {
    if (!mounted) {
      return;
    }
    setState(() {
      _ready = true;
      _session = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.go('/storage-failure');
    });
  }

  int _monotonic() => _origin + _clock.elapsedMilliseconds;

  void _syncOrigin(int documentMonotonic) {
    final int elapsed = _clock.elapsedMilliseconds;
    if (_origin + elapsed < documentMonotonic) {
      _origin = documentMonotonic - elapsed;
    }
  }

  void _followClock(LocalSession session) {
    const Set<String> counting = <String>{
      'preparing',
      'demonstrating',
      'active',
      'resting',
    };
    if (counting.contains(session.state)) {
      _clock.start();
    } else {
      _clock.stop();
    }
    if (session.state == 'resting') {
      _restTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else {
      _restTimer?.cancel();
      _restTimer = null;
    }
  }

  Future<void> _apply(String eventJson, {int? at}) async {
    if (_applying || _documentJson.isEmpty || _session == null) {
      return;
    }
    _applying = true;
    try {
      await _applyHeld(eventJson, at: at);
    } finally {
      _applying = false;
    }
  }

  Future<void> _applyHeld(String eventJson, {int? at}) async {
    final int now = at ?? _monotonic();
    final WorkoutView view = applyWorkoutEvent(
      documentJson: _documentJson,
      eventJson: eventJson,
      monotonicMillis: now,
    );
    if (view.outcome != 'ready' || view.documentJson.isEmpty) {
      return;
    }
    final LocalSession next;
    try {
      next = LocalSession.decode(view.documentJson);
    } catch (_) {
      return;
    }
    final bool terminal = next.outcome != null;
    final ProfileStore? store = widget.store;
    if (widget.previewDocument == null && store != null) {
      try {
        if (terminal) {
          await store.saveWorkoutTerminal(
            sessionId: next.sessionId,
            documentJson: view.documentJson,
          );
        } else {
          await store.saveWorkoutDraft(view.documentJson);
        }
      } catch (_) {
        _failStorage();
        return;
      }
    }
    var published = next;
    var publishedJson = view.documentJson;
    if (_pausePending &&
        !terminal &&
        (published.state == 'active' || published.state == 'resting')) {
      final WorkoutView paused = applyWorkoutEvent(
        documentJson: publishedJson,
        eventJson: '{"name":"pause"}',
        monotonicMillis: published.monotonicMs,
      );
      if (paused.outcome == 'ready' && paused.documentJson.isNotEmpty) {
        try {
          published = LocalSession.decode(paused.documentJson);
          publishedJson = paused.documentJson;
        } catch (_) {
          published = next;
          publishedJson = view.documentJson;
        }
      }
      if (published.state == 'paused' &&
          widget.previewDocument == null &&
          store != null) {
        try {
          await store.saveWorkoutDraft(publishedJson);
        } catch (_) {
          _failStorage();
          return;
        }
      }
    }
    if (!mounted) {
      return;
    }
    if (published.state != 'active' && published.state != 'resting') {
      _pausePending = false;
    }
    _documentJson = publishedJson;
    _session = published;
    _syncOrigin(published.monotonicMs);
    _reporting = false;
    if (_pausePending) {
      _clock.stop();
    } else {
      _followClock(published);
    }
    setState(() {});
  }

  Future<void> _commitPain() async {
    if (_session?.state != 'active' && _session?.state != 'resting') {
      return;
    }
    _clock.stop();
    await _apply(_painEvent(), at: _monotonic());
  }

  String _painEvent() {
    return jsonEncode(<String, Object>{
      'name': 'report_pain',
      'symptom': _symptom,
      'reported_pain': _pain,
    });
  }

  Future<void> _continuePain() async {
    await _commitPain();
    if (_session?.state == 'pain_check') {
      await _apply('{"name":"continue_after_pain"}');
    }
  }

  Future<void> _endPain() async {
    await _commitPain();
    if (_session?.state == 'pain_check') {
      await _apply('{"name":"end_session"}');
    }
  }

  Future<void> _skipRest() async {
    final int? until = _session?.restUntilMs;
    final int now = _monotonic();
    final int at = until == null || now >= until ? now : until;
    await _apply('{"name":"tick"}', at: at);
  }

  ExerciseDisplay? _display(String exerciseId) {
    final ExerciseDisplay? cached = _displays[exerciseId];
    if (cached != null) {
      return cached;
    }
    try {
      final ExerciseDisplay display = exerciseDisplay(exerciseId: exerciseId);
      _displays[exerciseId] = display;
      return display;
    } catch (_) {
      return null;
    }
  }

  SessionExercise? get _current {
    final LocalSession? session = _session;
    if (session == null) {
      return null;
    }
    for (final SessionExercise exercise in session.exercises) {
      final bool finished =
          exercise.skipped ||
          (exercise.repsDone >= exercise.reps &&
              exercise.setIndex + 1 >= exercise.sets);
      if (!finished) {
        return exercise;
      }
    }
    return session.exercises.isEmpty ? null : session.exercises.last;
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: Text('Loading session')));
    }
    if (_missing || _session == null) {
      return _missingScreen();
    }
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _children(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _missingScreen() {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('There is no saved session.'),
              const SizedBox(height: AppSpacing.space24),
              PrimaryButton(label: 'Home', onPressed: () => context.go('/')),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _children() {
    final LocalSession session = _session!;
    if (_reporting || session.state == 'pain_check') {
      return _painChildren(session);
    }
    switch (session.state) {
      case 'preparing':
        return _preparing(session);
      case 'demonstrating':
        return _demonstrating();
      case 'active':
        return _active();
      case 'resting':
        return _resting();
      case 'paused':
        return _paused(session);
      case 'completed':
        return _completed(session);
      case 'abandoned':
        return _ended(
          'Session ended',
          'This synthetic session was not saved as complete.',
          session,
        );
      case 'safety_stopped':
        return _ended(
          'Session stopped',
          'You ended this synthetic session. Nothing was marked complete.',
          session,
        );
      default:
        return _missingChildren();
    }
  }

  List<Widget> _missingChildren() {
    return const <Widget>[Text('There is no saved session.')];
  }

  List<Widget> _preparing(LocalSession session) {
    final SessionExercise? exercise = _current;
    final ExerciseDisplay? display = exercise == null
        ? null
        : _display(exercise.exerciseId);
    return <Widget>[
      const Text("Today's session"),
      const SizedBox(height: AppSpacing.space16),
      const Text('Synthetic session. Not a medical workout.'),
      const SizedBox(height: AppSpacing.space16),
      Text('About $_minutes minutes'),
      const SizedBox(height: AppSpacing.space16),
      Text(display?.name ?? ''),
      Text('${exercise?.sets ?? 0} × ${exercise?.reps ?? 0}'),
      const SizedBox(height: AppSpacing.space24),
      PrimaryButton(
        label: 'Start',
        onPressed: () => unawaited(_apply('{"name":"ready"}')),
      ),
    ];
  }

  List<Widget> _demonstrating() {
    final SessionExercise? exercise = _current;
    final ExerciseDisplay? display = exercise == null
        ? null
        : _display(exercise.exerciseId);
    return <Widget>[
      Text(display?.name ?? ''),
      const SizedBox(height: AppSpacing.space16),
      Text(display?.writtenInstructions ?? ''),
      const SizedBox(height: AppSpacing.space24),
      PrimaryButton(
        label: "I'm ready",
        onPressed: () => unawaited(_apply('{"name":"ready"}')),
      ),
    ];
  }

  List<Widget> _active() {
    final SessionExercise? exercise = _current;
    final ExerciseDisplay? display = exercise == null
        ? null
        : _display(exercise.exerciseId);
    final int setNumber = (exercise?.setIndex ?? 0) + 1;
    final int repNumber = (exercise?.repsDone ?? 0) + 1;
    return <Widget>[
      Text(display?.name ?? ''),
      const SizedBox(height: AppSpacing.space16),
      Text('Set $setNumber of ${exercise?.sets ?? 0}'),
      const SizedBox(height: AppSpacing.space8),
      PrimaryButton(
        label: 'Rep $repNumber of ${exercise?.reps ?? 0}',
        onPressed: () => unawaited(_apply('{"name":"complete_rep"}')),
      ),
      const SizedBox(height: AppSpacing.space16),
      Text(display?.writtenInstructions ?? ''),
      const SizedBox(height: AppSpacing.space24),
      SecondaryButton(
        label: 'Pause',
        onPressed: () => unawaited(_apply('{"name":"pause"}')),
      ),
      const SizedBox(height: AppSpacing.space12),
      SecondaryButton(
        label: 'This hurts',
        onPressed: () {
          _clock.stop();
          setState(() {
            _reporting = true;
            _symptom = 'mild_discomfort';
            _pain = 0;
          });
        },
      ),
      const SizedBox(height: AppSpacing.space12),
      TertiaryButton(
        label: 'Skip',
        onPressed: () => unawaited(_apply('{"name":"skip"}')),
      ),
    ];
  }

  List<Widget> _resting() {
    return <Widget>[
      const Text('Rest'),
      const SizedBox(height: AppSpacing.space16),
      Text('${_remainingSeconds()}'),
      const SizedBox(height: AppSpacing.space24),
      PrimaryButton(
        label: 'Skip rest',
        onPressed: () => unawaited(_skipRest()),
      ),
    ];
  }

  int _remainingSeconds() {
    final int? until = _session?.restUntilMs;
    if (until == null) {
      return 0;
    }
    final int delta = until - _monotonic();
    if (delta <= 0) {
      return 0;
    }
    return (delta + 999) ~/ 1000;
  }

  List<Widget> _paused(LocalSession session) {
    return <Widget>[
      const Text('Session paused'),
      const SizedBox(height: AppSpacing.space16),
      Text(_elapsedLabel(session.elapsedMs)),
      const SizedBox(height: AppSpacing.space24),
      PrimaryButton(
        label: 'Resume',
        onPressed: () => unawaited(_apply('{"name":"resume"}')),
      ),
      const SizedBox(height: AppSpacing.space12),
      SecondaryButton(
        label: 'Make session shorter',
        onPressed: () => unawaited(_apply('{"name":"shorten"}')),
      ),
      const SizedBox(height: AppSpacing.space12),
      SecondaryButton(
        label: 'Skip current exercise',
        onPressed: () => unawaited(_apply('{"name":"skip"}')),
      ),
      const SizedBox(height: AppSpacing.space12),
      SecondaryButton(
        label: 'End session',
        onPressed: () => unawaited(_apply('{"name":"end_session"}')),
      ),
    ];
  }

  List<Widget> _painChildren(LocalSession session) {
    final String selectedSymptom = session.state == 'pain_check' && !_reporting
        ? (session.symptom ?? _symptom)
        : _symptom;
    final int selectedPain = session.state == 'pain_check' && !_reporting
        ? (session.reportedPain ?? _pain)
        : _pain;
    const List<(String, String)> symptoms = <(String, String)>[
      ('Mild discomfort', 'mild_discomfort'),
      ('Sharp pain', 'sharp_pain'),
      ('Pain increased noticeably', 'increased'),
      ('Numbness / tingling', 'numbness_tingling'),
      ('Weakness / instability', 'weakness'),
    ];
    final bool stored = session.state == 'pain_check' && !_reporting;
    return <Widget>[
      const Text('Exercise paused'),
      const SizedBox(height: AppSpacing.space16),
      for (final (String label, String token) in symptoms) ...<Widget>[
        _choice(
          label: label,
          selected: selectedSymptom == token,
          onPressed: stored
              ? null
              : () {
                  setState(() {
                    _symptom = token;
                    _reporting = true;
                  });
                },
        ),
        const SizedBox(height: AppSpacing.space8),
      ],
      Wrap(
        spacing: AppSpacing.space8,
        runSpacing: AppSpacing.space8,
        children: <Widget>[
          for (int value = 0; value <= 10; value++)
            _choice(
              label: '$value',
              selected: selectedPain == value,
              onPressed: stored
                  ? null
                  : () {
                      setState(() {
                        _pain = value;
                        _reporting = true;
                      });
                    },
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.space24),
      PrimaryButton(
        label: 'Continue',
        onPressed: () => unawaited(_continuePain()),
      ),
      const SizedBox(height: AppSpacing.space12),
      SecondaryButton(
        label: 'End session',
        onPressed: () => unawaited(_endPain()),
      ),
    ];
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
  }) {
    final Widget button = selected
        ? PrimaryButton(label: label, onPressed: onPressed)
        : SecondaryButton(label: label, onPressed: onPressed);
    return Semantics(
      selected: selected,
      enabled: onPressed != null,
      child: button,
    );
  }

  List<Widget> _completed(LocalSession session) {
    final int reps = session.exercises.fold<int>(
      0,
      (int sum, SessionExercise exercise) => sum + exercise.repsDone,
    );
    final int exercises = session.exercises.length;
    final String exerciseWord = exercises == 1 ? 'exercise' : 'exercises';
    final String repWord = reps == 1 ? 'rep' : 'reps';
    return <Widget>[
      const Text('Session saved'),
      const SizedBox(height: AppSpacing.space16),
      Text('$exercises $exerciseWord. $reps completed $repWord.'),
      const SizedBox(height: AppSpacing.space24),
      PrimaryButton(label: 'Home', onPressed: () => context.go('/')),
      const SizedBox(height: AppSpacing.space12),
      SecondaryButton(
        label: 'Report a problem',
        onPressed: () =>
            context.go('/focus/report?session=${session.sessionId}'),
      ),
    ];
  }

  List<Widget> _ended(String title, String sentence, LocalSession session) {
    return <Widget>[
      Text(title),
      const SizedBox(height: AppSpacing.space16),
      Text(sentence),
      const SizedBox(height: AppSpacing.space24),
      PrimaryButton(label: 'Home', onPressed: () => context.go('/')),
      const SizedBox(height: AppSpacing.space12),
      SecondaryButton(
        label: 'Report a problem',
        onPressed: () =>
            context.go('/focus/report?session=${session.sessionId}'),
      ),
    ];
  }

  String _elapsedLabel(int milliseconds) {
    final int total = milliseconds <= 0 ? 0 : milliseconds ~/ 1000;
    final int minutes = total ~/ 60;
    final int seconds = total % 60;
    final String padded = seconds.toString().padLeft(2, '0');
    return '$minutes:$padded';
  }
}
