import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_radius.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/pain_slider.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/intake/intake_controller.dart';
import 'package:helpmemove/intake/intake_draft.dart';
import 'package:helpmemove/intake/intake_outcome.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';

class IntakeUnavailable extends StatelessWidget {
  const IntakeUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: Center(
            child: PrimaryButton(
              label: 'Back',
              onPressed: () => context.go('/'),
            ),
          ),
        ),
      ),
    );
  }
}

class IntakeFlow extends StatefulWidget {
  const IntakeFlow({super.key, required this.store, required this.initialStep});

  final ProfileStore store;
  final String initialStep;

  @override
  State<IntakeFlow> createState() => _IntakeFlowState();
}

class _IntakeFlowState extends State<IntakeFlow> {
  late final IntakeController _controller = IntakeController(
    store: widget.store,
  );
  late final TextEditingController _noteController = TextEditingController();

  IntakeVocabulary? _vocabulary;
  SafetyView? _view;
  String _laterality = 'bilateral';
  bool _front = true;
  bool _ready = false;
  bool _loadFailed = false;
  bool _busy = false;
  String? _error;

  String get _step {
    if (intakeSteps.contains(widget.initialStep)) {
      return widget.initialStep;
    }
    return 'intent';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(IntakeFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStep != widget.initialStep) {
      _view = null;
      _busy = false;
      _error = null;
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final IntakeVocabulary vocabulary = intakeVocabulary();
      await _controller.load();
      _vocabulary = vocabulary;
      _noteController.text = _controller.draft.note;
      _loadFailed = false;
      if (_step == 'check') {
        _view = await _classifyOrBridge();
      }
    } catch (_) {
      _loadFailed = true;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _ready = true;
    });
  }

  Future<void> _continue() async {
    if (_busy || !_canContinue) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final String step = _step;
    if (step == 'notice') {
      _controller.draft.noticeId = 'syn-notice-1';
      _controller.draft.schemaAck = 'yes';
    }
    final String? next = _next(step);
    if (next != null) {
      _controller.draft.step = next;
    }
    try {
      await _controller.save();
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
    if (step == 'check') {
      final SafetyView view = await _classifyOrBridge();
      if (!mounted) {
        return;
      }
      setState(() {
        _view = view;
        _busy = false;
      });
      return;
    }
    if (next != null) {
      context.go('/focus/intake?step=$next');
    }
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<SafetyView> _classifyOrBridge() async {
    try {
      return await _controller.classify();
    } catch (_) {
      return const SafetyView(
        code: 'bridge',
        level: '',
        escalation: '',
        permitsOrdinaryGeneration: false,
        emergencyDisplay: '',
        emergencyCode: 'region',
      );
    }
  }

  Future<void> _startOver() async {
    try {
      await _controller.delete();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'The draft could not be removed.';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    _noteController.text = '';
    setState(() {
      _view = null;
      _error = null;
      _loadFailed = false;
      _ready = false;
      _vocabulary = null;
      _laterality = 'bilateral';
      _front = true;
      _busy = false;
    });
    final String step =
        GoRouterState.of(context).uri.queryParameters['step'] ?? 'intent';
    if (step != 'intent') {
      context.go('/focus/intake?step=intent');
    }
    await _load();
  }

  void _back() {
    if (_view != null) {
      setState(() {
        _view = null;
      });
      return;
    }
    final String? previous = _previous(_step);
    if (previous == null) {
      context.go('/');
      return;
    }
    context.go('/focus/intake?step=$previous');
  }

  bool get _canContinue {
    final LocalIntakeDraft draft = _controller.draft;
    switch (_step) {
      case 'intent':
        return draft.intent != null;
      case 'goals':
        return draft.goals.isNotEmpty;
      case 'equipment':
        return draft.equipment.isNotEmpty;
      case 'body':
        return draft.areas.isNotEmpty;
      default:
        return true;
    }
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
        title: Text(_title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: _ready ? _body() : const Center(child: Text('Loading intake')),
        ),
      ),
    );
  }

  String get _title {
    switch (_step) {
      case 'intent':
        return 'What brings you here';
      case 'notice':
        return 'A note about this fixture';
      case 'goals':
        return 'Goals';
      case 'equipment':
        return 'Equipment';
      case 'body':
        return 'Where it feels limited';
      case 'note':
        return 'A note for you';
      case 'severity':
        return 'How strong is it right now';
      case 'check':
        return 'Safety check';
      default:
        return 'Intake';
    }
  }

  Widget _body() {
    if (_loadFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('The saved draft could not be opened.'),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.space12),
            Text(_error!),
          ],
          const SizedBox(height: AppSpacing.space24),
          PrimaryButton(
            label: 'Start over',
            onPressed: () => unawaited(_startOver()),
          ),
        ],
      );
    }
    final SafetyView? view = _view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: view == null
                    ? _stepBody()
                    : IntakeOutcome(
                        view: view,
                        onStartOver: () => unawaited(_startOver()),
                      ),
              ),
              if (view == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.space24),
                      child: PrimaryButton(
                        label: 'Continue',
                        loading: _busy,
                        onPressed: _canContinue
                            ? () => unawaited(_continue())
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.space12),
          Text(_error!),
        ],
      ],
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 'intent':
        return _intent();
      case 'notice':
        return const Text(
          'Continuing records schema acknowledgment syn-notice-1. This is not a medical assessment.',
        );
      case 'goals':
        return _tokens(
          _vocabulary?.goals ?? const <String>[],
          _controller.draft.goals,
        );
      case 'equipment':
        return _tokens(
          _vocabulary?.equipment ?? const <String>[],
          _controller.draft.equipment,
        );
      case 'body':
        return _bodyStep();
      case 'note':
        return _note();
      case 'severity':
        return PainSlider(
          value: _controller.draft.severity,
          onChanged: (int value) {
            setState(() {
              _controller.draft.severity = value;
            });
          },
        );
      case 'check':
        return const Text('The clinician question list is not available.');
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _intent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _choice(
          'Something hurts or feels limited',
          _controller.draft.intent == 'pain_or_limit',
          () => _setIntent('pain_or_limit'),
        ),
        _choice(
          'I want general movement',
          _controller.draft.intent == 'fitness',
          () => _setIntent('fitness'),
        ),
        _choice(
          'I am not sure',
          _controller.draft.intent == 'not_sure',
          () => _setIntent('not_sure'),
        ),
      ],
    );
  }

  void _setIntent(String intent) {
    setState(() {
      _controller.draft.intent = intent;
    });
  }

  Widget _tokens(List<String> tokens, List<String> selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final String token in tokens)
          _choice(_present(token), selected.contains(token), () {
            setState(() {
              if (selected.contains(token)) {
                selected.remove(token);
              } else {
                selected.add(token);
              }
            });
          }),
      ],
    );
  }

  Widget _bodyStep() {
    final List<String> regions = _vocabulary?.regions ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.space8,
          runSpacing: AppSpacing.space8,
          children: [
            _choice('Front', _front, () => setState(() => _front = true)),
            _choice('Back', !_front, () => setState(() => _front = false)),
          ],
        ),
        const SizedBox(height: AppSpacing.space12),
        Text(_front ? 'Front' : 'Back'),
        const SizedBox(height: AppSpacing.space8),
        const Text('Front and back use the same seven regions.'),
        const SizedBox(height: AppSpacing.space12),
        const Text('Map'),
        const SizedBox(height: AppSpacing.space8),
        _bodyMap(regions),
        const SizedBox(height: AppSpacing.space16),
        Wrap(
          spacing: AppSpacing.space8,
          runSpacing: AppSpacing.space8,
          children: [
            _choice(
              'Left',
              _laterality == 'left',
              () => _setLaterality('left'),
            ),
            _choice(
              'Right',
              _laterality == 'right',
              () => _setLaterality('right'),
            ),
            _choice(
              'Both',
              _laterality == 'bilateral',
              () => _setLaterality('bilateral'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space16),
        const Text('List'),
        const SizedBox(height: AppSpacing.space8),
        for (final String region in regions)
          _regionTile('list-$region', region),
      ],
    );
  }

  void _setLaterality(String laterality) {
    setState(() {
      _laterality = laterality;
    });
  }

  Widget _bodyMap(List<String> regions) {
    final AppColors colors = appColorsOf(context);
    final Set<String> known = regions.toSet();
    const double width = 260;
    const double height = 430;
    return Center(
      child: KeyedSubtree(
        key: Key(_front ? 'body-front' : 'body-back'),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              if (known.contains('head_neck'))
                Positioned(
                  left: 90,
                  top: 0,
                  child: _mapHit(
                    token: 'head_neck',
                    keyName: 'map-head_neck',
                    width: 80,
                    height: 72,
                    radius: 36,
                    colors: colors,
                    shortLabel: 'Head',
                  ),
                ),
              if (known.contains('shoulder'))
                Positioned(
                  left: 30,
                  top: 68,
                  child: _mapHit(
                    token: 'shoulder',
                    keyName: 'map-shoulder',
                    width: 200,
                    height: 32,
                    radius: 12,
                    colors: colors,
                    shortLabel: 'Shoulders',
                  ),
                ),
              if (known.contains('arm')) ...[
                Positioned(
                  left: 0,
                  top: 100,
                  child: _mapHit(
                    token: 'arm',
                    keyName: 'map-arm',
                    width: 52,
                    height: 118,
                    radius: 18,
                    colors: colors,
                    shortLabel: 'Arm',
                  ),
                ),
                Positioned(
                  left: 208,
                  top: 100,
                  child: _mapHit(
                    token: 'arm',
                    keyName: 'map-arm-right',
                    width: 52,
                    height: 118,
                    radius: 18,
                    colors: colors,
                    shortLabel: 'Arm',
                  ),
                ),
              ],
              if (known.contains('torso'))
                Positioned(
                  left: 78,
                  top: 104,
                  child: _mapHit(
                    token: 'torso',
                    keyName: 'map-torso',
                    width: 104,
                    height: 112,
                    radius: 18,
                    colors: colors,
                    shortLabel: 'Torso',
                  ),
                ),
              if (known.contains('pelvis'))
                Positioned(
                  left: 84,
                  top: 214,
                  child: _mapHit(
                    token: 'pelvis',
                    keyName: 'map-pelvis',
                    width: 92,
                    height: 40,
                    radius: 14,
                    colors: colors,
                    shortLabel: 'Pelvis',
                  ),
                ),
              if (known.contains('leg')) ...[
                Positioned(
                  left: 84,
                  top: 254,
                  child: _mapHit(
                    token: 'leg',
                    keyName: 'map-leg',
                    width: 40,
                    height: 124,
                    radius: 16,
                    colors: colors,
                    shortLabel: 'Leg',
                  ),
                ),
                Positioned(
                  left: 136,
                  top: 254,
                  child: _mapHit(
                    token: 'leg',
                    keyName: 'map-leg-right',
                    width: 40,
                    height: 124,
                    radius: 16,
                    colors: colors,
                    shortLabel: 'Leg',
                  ),
                ),
              ],
              if (known.contains('foot')) ...[
                Positioned(
                  left: 72,
                  top: 378,
                  child: _mapHit(
                    token: 'foot',
                    keyName: 'map-foot',
                    width: 56,
                    height: 40,
                    radius: 12,
                    colors: colors,
                    shortLabel: 'Foot',
                  ),
                ),
                Positioned(
                  left: 132,
                  top: 378,
                  child: _mapHit(
                    token: 'foot',
                    keyName: 'map-foot-right',
                    width: 56,
                    height: 40,
                    radius: 12,
                    colors: colors,
                    shortLabel: 'Foot',
                  ),
                ),
              ],
              if (!_front)
                IgnorePointer(
                  child: CustomPaint(
                    key: const Key('body-spine'),
                    size: const Size(width, height),
                    painter: _BodyOutlinePainter(color: colors.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapHit({
    required String token,
    required String keyName,
    required double width,
    required double height,
    required double radius,
    required AppColors colors,
    required String shortLabel,
  }) {
    final IntakeArea? area = _areaFor(token);
    final bool selected = area != null;
    final String suffix = area == null
        ? ''
        : ' ${_lateralityLabel(area.laterality)}';
    final String label = '${_present(token)}$suffix';
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          key: Key(keyName),
          color: selected
              ? colors.accent.withValues(alpha: 0.30)
              : colors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radius)),
            side: BorderSide(
              color: selected ? colors.accent : colors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () => _toggleRegion(token),
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(radius)),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(shortLabel, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _regionTile(String keyName, String region) {
    final IntakeArea? area = _areaFor(region);
    final bool selected = area != null;
    final String suffix = area == null
        ? ''
        : ' ${_lateralityLabel(area.laterality)}';
    return _choice(
      '${_present(region)}$suffix',
      selected,
      () => _toggleRegion(region),
      tileKey: Key(keyName),
    );
  }

  IntakeArea? _areaFor(String region) {
    for (final IntakeArea area in _controller.draft.areas) {
      if (area.region == region) {
        return area;
      }
    }
    return null;
  }

  void _toggleRegion(String region) {
    final List<IntakeArea> areas = _controller.draft.areas;
    final int index = areas.indexWhere(
      (IntakeArea area) => area.region == region,
    );
    setState(() {
      if (index >= 0 && areas[index].laterality == _laterality) {
        areas.removeAt(index);
      } else if (index >= 0) {
        areas[index] = IntakeArea(region: region, laterality: _laterality);
      } else {
        areas.add(IntakeArea(region: region, laterality: _laterality));
      }
    });
  }

  Widget _note() {
    final int count = _controller.draft.note.runes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('intake-note'),
          controller: _noteController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Optional note'),
          onChanged: (String value) {
            final String limited = _limitNote(value);
            if (limited != value) {
              _noteController.value = TextEditingValue(
                text: limited,
                selection: TextSelection.collapsed(offset: limited.length),
              );
            }
            setState(() {
              _controller.draft.note = limited;
            });
          },
        ),
        const SizedBox(height: AppSpacing.space8),
        Text('$count of 200'),
      ],
    );
  }

  Widget _choice(
    String label,
    bool selected,
    VoidCallback onTap, {
    Key? tileKey,
  }) {
    final AppColors colors = appColorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space8),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          key: tileKey,
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
            onTap: onTap,
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

String? _next(String step) {
  final int index = intakeSteps.indexOf(step);
  if (index < 0 || index + 1 >= intakeSteps.length) {
    return null;
  }
  return intakeSteps[index + 1];
}

String? _previous(String step) {
  final int index = intakeSteps.indexOf(step);
  if (index <= 0) {
    return null;
  }
  return intakeSteps[index - 1];
}

String _present(String token) {
  if (token == 'head_neck') {
    return 'Head and neck';
  }
  final String spaced = token.replaceAll('_', ' ');
  if (spaced.isEmpty) {
    return token;
  }
  return spaced[0].toUpperCase() + spaced.substring(1);
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

String _limitNote(String value) {
  final List<int> scalars = value.runes.toList();
  if (scalars.length <= 200) {
    return value;
  }
  return String.fromCharCodes(scalars.take(200));
}

class _BodyOutlinePainter extends CustomPainter {
  const _BodyOutlinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(130, 118), const Offset(130, 360), line);
  }

  @override
  bool shouldRepaint(_BodyOutlinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
