import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/assessment/assessment_document.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_radius.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/secondary_button.dart';
import 'package:helpmemove/design/components/tertiary_button.dart';
import 'package:helpmemove/intake/intake_draft.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';

/// Gate-false route. No form and no write.
class AssessmentBlocked extends StatelessWidget {
  const AssessmentBlocked({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'The synthetic rule is not allowing a movement check.',
              ),
              const SizedBox(height: AppSpacing.space24),
              PrimaryButton(label: 'Home', onPressed: () => context.go('/')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Open gate without a profile. No form and no write.
class AssessmentUnavailable extends StatelessWidget {
  const AssessmentUnavailable({super.key});

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

class AssessmentFlow extends StatefulWidget {
  const AssessmentFlow({
    super.key,
    required this.store,
    required this.initialStep,
    this.planAllowed = false,
  });

  final ProfileStore store;
  final String initialStep;

  /// True only when the in-memory movement gate is open. Not a query parameter.
  final bool planAllowed;

  @override
  State<AssessmentFlow> createState() => _AssessmentFlowState();
}

class _AssessmentFlowState extends State<AssessmentFlow> {
  LocalAssessment? _draft;
  List<IntakeArea> _intakeAreas = <IntakeArea>[];
  List<String> _ratings = <String>[];
  String? _selected;
  String _instrumentId = 'syn-assessment-core';
  bool _ready = false;
  bool _unreadable = false;
  bool _storageFailed = false;
  bool _intakeUnusable = true;
  bool _instrumentReady = false;
  bool _busy = false;
  String? _error;

  String get _step {
    switch (widget.initialStep) {
      case 'intro':
      case 'area':
      case 'summary':
        return widget.initialStep;
      default:
        return 'intro';
    }
  }

  String get _screen {
    if (_storageFailed) {
      return 'storage';
    }
    if (_unreadable) {
      return 'unreadable';
    }
    if (_draft == null) {
      if (_step == 'area' && _intakeUnusable) {
        return 'intake-unusable';
      }
      return 'intro';
    }
    if (_step == 'intro') {
      return 'intro';
    }
    if (_intakeUnusable) {
      return 'intake-unusable';
    }
    if (_step == 'summary') {
      return 'summary';
    }
    if (_draft!.stopped || _nextArea() == null) {
      return 'summary';
    }
    return 'area';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(AssessmentFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStep != widget.initialStep) {
      _selected = null;
      _busy = false;
      _error = null;
    }
  }

  Future<void> _load() async {
    var unreadable = false;
    var storageFailed = false;
    LocalAssessment? draft;
    try {
      final String? assessmentRaw = await widget.store.loadAssessmentDraft();
      if (assessmentRaw != null) {
        try {
          draft = LocalAssessment.decode(assessmentRaw);
        } catch (_) {
          unreadable = true;
        }
      }
    } catch (_) {
      storageFailed = true;
      draft = null;
      unreadable = false;
    }
    if (storageFailed) {
      if (!mounted) {
        return;
      }
      setState(() {
        _storageFailed = true;
        _draft = null;
        _unreadable = false;
        _ready = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context.go('/storage-failure');
      });
      return;
    }

    var instrumentReady = false;
    var instrumentId = 'syn-assessment-core';
    var ratings = <String>[];
    var regions = <String>[];
    try {
      final AssessmentInstrumentView instrument = loadCommittedInstrument();
      if (instrument.instrumentId == 'syn-assessment-core') {
        instrumentId = instrument.instrumentId;
        instrumentReady = true;
      }
      ratings = assessmentVocabulary().ratings;
      regions = intakeVocabulary().regions;
    } catch (_) {
      instrumentReady = false;
    }

    var intakeUnusable = true;
    var intakeAreas = <IntakeArea>[];
    try {
      final String? intakeRaw = await widget.store.loadDraft();
      if (intakeRaw != null && regions.isNotEmpty) {
        final LocalIntakeDraft intake = LocalIntakeDraft.decode(intakeRaw);
        intakeAreas = _areasInOrder(intake, regions);
        intakeUnusable = intakeAreas.isEmpty;
      }
    } catch (_) {
      intakeUnusable = true;
      intakeAreas = <IntakeArea>[];
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _draft = draft;
      _intakeAreas = intakeAreas;
      _ratings = ratings;
      _unreadable = unreadable;
      _storageFailed = storageFailed;
      _intakeUnusable = intakeUnusable;
      _instrumentReady = instrumentReady;
      _instrumentId = instrumentId;
      _ready = true;
    });
  }

  Future<void> _start() async {
    if (_busy || !_instrumentReady || _storageFailed) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_intakeUnusable || _intakeAreas.isEmpty) {
      if (!mounted) {
        return;
      }
      context.go('/focus/assessment?step=area');
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
      });
      return;
    }
    if (_draft == null) {
      final LocalAssessment created = LocalAssessment();
      final bool saved = await _persist(created);
      if (!saved || !mounted) {
        return;
      }
      _draft = created;
    }
    final LocalAssessment draft = _draft!;
    final String next = draft.stopped || _nextArea() == null
        ? 'summary'
        : 'area';
    if (!mounted) {
      return;
    }
    context.go('/focus/assessment?step=$next');
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
    });
  }

  Future<void> _continue() async {
    if (_busy) {
      return;
    }
    final LocalAssessment? draft = _draft;
    final IntakeArea? area = _nextArea();
    final String? selected = _selected;
    if (draft == null || area == null || selected == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final AssessmentArea added = AssessmentArea(
      region: area.region,
      laterality: area.laterality,
      rating: selected,
    );
    draft.areas.add(added);
    draft.stopped = false;
    final bool previousComplete = draft.complete;
    draft.complete = _completeFor(draft);
    final bool saved = await _persist(draft);
    if (!saved) {
      draft.areas.remove(added);
      draft.complete = previousComplete;
      return;
    }
    if (!mounted) {
      return;
    }
    _selected = null;
    if (_nextArea() == null) {
      context.go('/focus/assessment?step=summary');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
    });
  }

  Future<void> _skip() async {
    if (_busy) {
      return;
    }
    final LocalAssessment? draft = _draft;
    final IntakeArea? area = _nextArea();
    if (draft == null || area == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final AssessmentArea added = AssessmentArea(
      region: area.region,
      laterality: area.laterality,
      rating: null,
    );
    draft.areas.add(added);
    draft.stopped = false;
    final bool previousComplete = draft.complete;
    draft.complete = _completeFor(draft);
    final bool saved = await _persist(draft);
    if (!saved) {
      draft.areas.remove(added);
      draft.complete = previousComplete;
      return;
    }
    if (!mounted) {
      return;
    }
    _selected = null;
    if (_nextArea() == null) {
      context.go('/focus/assessment?step=summary');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
    });
  }

  Future<void> _stop() async {
    if (_busy) {
      return;
    }
    final LocalAssessment? draft = _draft;
    if (draft == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final IntakeArea? area = _nextArea();
    final String? selected = _selected;
    AssessmentArea? added;
    if (area != null && selected != null) {
      added = AssessmentArea(
        region: area.region,
        laterality: area.laterality,
        rating: selected,
      );
      draft.areas.add(added);
    }
    final bool previousStopped = draft.stopped;
    final bool previousComplete = draft.complete;
    draft.stopped = true;
    draft.complete = false;
    final bool saved = await _persist(draft);
    if (!saved) {
      if (added != null) {
        draft.areas.remove(added);
      }
      draft.stopped = previousStopped;
      draft.complete = previousComplete;
      return;
    }
    if (!mounted) {
      return;
    }
    _selected = null;
    context.go('/focus/assessment?step=summary');
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
    });
  }

  Future<void> _done() async {
    final LocalAssessment? document = _draft;
    if (_busy || document == null || _intakeUnusable || _intakeAreas.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    document.complete = document.stopped ? false : _completeFor(document);
    try {
      await widget.store.saveAssessmentRecord(document.encode());
      await widget.store.deleteAssessmentDraft();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = 'The draft could not be saved.';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    context.go('/');
  }

  Future<void> _openPlan() async {
    final LocalAssessment? document = _draft;
    if (_busy ||
        document == null ||
        !widget.planAllowed ||
        document.stopped ||
        !_completeFor(document)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    document.complete = true;
    try {
      await widget.store.saveAssessmentRecord(document.encode());
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = 'The draft could not be saved.';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    context.go('/focus/program');
  }

  Future<void> _startOver() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.deleteAssessmentDraft();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = 'The draft could not be removed.';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _draft = null;
      _unreadable = false;
      _selected = null;
      _busy = false;
      _error = null;
    });
    final String step =
        GoRouterState.of(context).uri.queryParameters['step'] ?? 'intro';
    if (step != 'intro') {
      context.go('/focus/assessment?step=intro');
    }
  }

  void _back() {
    if (_screen == 'intro' ||
        _screen == 'unreadable' ||
        _screen == 'intake-unusable') {
      context.go('/');
      return;
    }
    context.go('/focus/assessment?step=intro');
  }

  Future<bool> _persist(LocalAssessment document) async {
    try {
      await widget.store.saveAssessmentDraft(document.encode());
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The draft could not be saved.';
        });
      }
      return false;
    }
    return true;
  }

  IntakeArea? _nextArea() {
    final LocalAssessment? draft = _draft;
    if (draft == null) {
      return null;
    }
    final Set<String> asked = <String>{
      for (final AssessmentArea area in draft.areas) area.region,
    };
    for (final IntakeArea area in _intakeAreas) {
      if (!asked.contains(area.region)) {
        return area;
      }
    }
    return null;
  }

  bool _completeFor(LocalAssessment document) {
    if (document.stopped || _intakeAreas.isEmpty) {
      return false;
    }
    if (document.areas.length != _intakeAreas.length) {
      return false;
    }
    for (final IntakeArea expected in _intakeAreas) {
      AssessmentArea? found;
      for (final AssessmentArea area in document.areas) {
        if (area.region == expected.region) {
          found = area;
          break;
        }
      }
      if (found == null ||
          found.laterality != expected.laterality ||
          found.rating == null) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(_ready ? _title : 'Movement check'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: _ready
              ? _body()
              : const Center(child: Text('Loading movement check')),
        ),
      ),
    );
  }

  String get _title {
    switch (_screen) {
      case 'area':
        final IntakeArea? area = _nextArea();
        if (area == null) {
          return 'Movement check';
        }
        return _areaTitle(area.region, area.laterality);
      case 'intro':
        return "Let's see how you move";
      default:
        return 'Movement check';
    }
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [SliverToBoxAdapter(child: _screenBody())],
          ),
        ),
        if (_error != null && _screen != 'unreadable') ...[
          const SizedBox(height: AppSpacing.space12),
          Text(_error!),
        ],
      ],
    );
  }

  Widget _screenBody() {
    switch (_screen) {
      case 'storage':
        return const SizedBox.shrink();
      case 'unreadable':
        return _unreadableBody();
      case 'intake-unusable':
        return _intakeUnusableBody();
      case 'area':
        return _areaBody();
      case 'summary':
        return _summaryBody();
      default:
        return _introBody();
    }
  }

  Widget _introBody() {
    if (!_instrumentReady) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('The movement check could not be opened.'),
          const SizedBox(height: AppSpacing.space24),
          PrimaryButton(label: 'Home', onPressed: () => context.go('/')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This check uses $_instrumentId. It is not a medical assessment. It does not measure angles.',
        ),
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(
          label: 'Start movement check',
          onPressed: _busy ? null : () => unawaited(_start()),
        ),
        const SizedBox(height: AppSpacing.space12),
        TertiaryButton(
          label: 'Start over',
          onPressed: _busy ? null : () => unawaited(_startOver()),
        ),
      ],
    );
  }

  Widget _unreadableBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('The saved movement check could not be opened.'),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.space12),
          Text(_error!),
        ],
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(
          label: 'Start over',
          onPressed: _busy ? null : () => unawaited(_startOver()),
        ),
      ],
    );
  }

  Widget _intakeUnusableBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('The saved intake could not be used for this check.'),
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(label: 'Home', onPressed: () => context.go('/')),
      ],
    );
  }

  Widget _areaBody() {
    final IntakeArea? area = _nextArea();
    if (area == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final String token in _ratings)
          _choice(_ratingLabel(token), _selected == token, () {
            setState(() {
              _selected = token;
            });
          }),
        const SizedBox(height: AppSpacing.space8),
        SecondaryButton(
          label: 'Skip',
          onPressed: _busy ? null : () => unawaited(_skip()),
        ),
        const SizedBox(height: AppSpacing.space12),
        SecondaryButton(
          label: 'Stop',
          onPressed: _busy ? null : () => unawaited(_stop()),
        ),
        const SizedBox(height: AppSpacing.space12),
        TertiaryButton(
          label: 'Start over',
          onPressed: _busy ? null : () => unawaited(_startOver()),
        ),
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(
          label: 'Continue',
          onPressed: _selected == null || _busy
              ? null
              : () => unawaited(_continue()),
        ),
      ],
    );
  }

  Widget _summaryBody() {
    final LocalAssessment? draft = _draft;
    if (draft == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final AssessmentArea area in draft.areas) ...[
          Text(_areaTitle(area.region, area.laterality)),
          Text(area.rating == null ? 'Skipped' : _ratingLabel(area.rating!)),
          const SizedBox(height: AppSpacing.space12),
        ],
        Text(
          _completeFor(draft)
              ? 'Saved on this device. No exercise program is created.'
              : 'This check is incomplete. No exercise program is created.',
        ),
        if (widget.planAllowed &&
            !draft.stopped &&
            _completeFor(draft)) ...<Widget>[
          const SizedBox(height: AppSpacing.space24),
          SecondaryButton(
            label: 'Check starting plan',
            onPressed: _busy ? null : () => unawaited(_openPlan()),
          ),
        ],
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(
          label: 'Done',
          onPressed: _busy ? null : () => unawaited(_done()),
        ),
        const SizedBox(height: AppSpacing.space12),
        TertiaryButton(
          label: 'Start over',
          onPressed: _busy ? null : () => unawaited(_startOver()),
        ),
      ],
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    final AppColors colors = appColorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space8),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected
              ? colors.accent.withValues(alpha: 0.30)
              : colors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadius.medium),
            ),
            side: BorderSide(
              color: selected ? colors.accent : colors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: _busy ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16,
                  vertical: AppSpacing.space12,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(label),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<IntakeArea> _areasInOrder(LocalIntakeDraft intake, List<String> regions) {
  final List<IntakeArea> ordered = <IntakeArea>[];
  for (final String region in regions) {
    for (final IntakeArea area in intake.areas) {
      if (area.region == region) {
        ordered.add(area);
      }
    }
  }
  return ordered;
}

String _areaTitle(String region, String laterality) {
  return '${_regionLabel(region)} ${_lateralityLabel(laterality)}';
}

String _regionLabel(String token) {
  if (token == 'head_neck') {
    return 'Head and neck';
  }
  return _capitalize(token);
}

String _lateralityLabel(String token) {
  switch (token) {
    case 'left':
      return 'Left';
    case 'right':
      return 'Right';
    case 'bilateral':
      return 'Both';
    default:
      return token;
  }
}

String _ratingLabel(String token) {
  return _capitalize(token);
}

String _capitalize(String token) {
  final String spaced = token.replaceAll('_', ' ');
  if (spaced.isEmpty) {
    return token;
  }
  return spaced[0].toUpperCase() + spaced.substring(1);
}
