import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/secondary_button.dart';
import 'package:helpmemove/program/program_document.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';

/// Gate-false route. No compose call and no write.
class ProgramBlocked extends StatelessWidget {
  const ProgramBlocked({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('The synthetic rule is not allowing a starting plan.'),
              const SizedBox(height: AppSpacing.space24),
              PrimaryButton(label: 'Home', onPressed: () => context.go('/')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Open gate without a profile. No compose call and no write.
class ProgramUnavailable extends StatelessWidget {
  const ProgramUnavailable({super.key});

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

class ProgramFlow extends StatefulWidget {
  const ProgramFlow({super.key, required this.store, this.preview});

  final ProfileStore store;
  final LocalProgram? preview;

  @override
  State<ProgramFlow> createState() => _ProgramFlowState();
}

class _ShownExercise {
  const _ShownExercise({
    required this.name,
    required this.instructions,
    required this.exercise,
  });

  final String name;
  final String instructions;
  final ProgramExercise exercise;
}

class _ProgramFlowState extends State<ProgramFlow> {
  bool _ready = false;
  bool _withheld = false;
  bool _storageFailed = false;
  LocalProgram? _program;
  List<_ShownExercise> _shown = <_ShownExercise>[];

  @override
  void initState() {
    super.initState();
    final LocalProgram? preview = widget.preview;
    if (preview != null) {
      _applyProgram(preview);
      return;
    }
    unawaited(_load());
  }

  void _applyProgram(LocalProgram program) {
    try {
      program.validate();
      _program = program;
      _shown = _shownFrom(program, loadFixture: false);
      _withheld = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _program != program) {
          return;
        }
        final List<_ShownExercise> shown = _shownFrom(
          program,
          loadFixture: true,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _shown = shown;
        });
      });
    } catch (_) {
      _program = null;
      _shown = <_ShownExercise>[];
      _withheld = true;
    }
    _ready = true;
  }

  Future<void> _load() async {
    String? intake;
    String? assessment;
    try {
      intake = await widget.store.loadDraft();
      assessment = await widget.store.loadAssessmentRecord();
    } catch (_) {
      _failStorage();
      return;
    }
    if (!mounted) {
      return;
    }
    final StartingPlan plan = composeStartingPlan(
      intakeDocument: intake ?? '',
      assessmentDocument: assessment ?? '',
      nowUnixMillis: widget.store.clock().toUtc().millisecondsSinceEpoch,
    );
    if (plan.outcome == 'ready' && plan.documentJson.isNotEmpty) {
      final LocalProgram? program = _decode(plan.documentJson);
      if (program == null) {
        _showWithheld();
        return;
      }
      try {
        await widget.store.saveProgramRecord(plan.documentJson);
      } catch (_) {
        _failStorage();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _applyProgram(program);
      });
      return;
    }
    _showWithheld();
  }

  LocalProgram? _decode(String raw) {
    try {
      return LocalProgram.decode(raw);
    } catch (_) {
      return null;
    }
  }

  void _showWithheld() {
    if (!mounted) {
      return;
    }
    setState(() {
      _program = null;
      _shown = <_ShownExercise>[];
      _withheld = true;
      _ready = true;
    });
  }

  void _failStorage() {
    if (!mounted) {
      return;
    }
    setState(() {
      _storageFailed = true;
      _program = null;
      _withheld = false;
      _ready = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.go('/storage-failure');
    });
  }

  List<_ShownExercise> _shownFrom(
    LocalProgram program, {
    required bool loadFixture,
  }) {
    return <_ShownExercise>[
      for (final ProgramExercise exercise in program.exercises)
        _ShownExercise(
          name: loadFixture
              ? _fixtureName(exercise.exerciseId)
              : exercise.exerciseId,
          instructions: loadFixture
              ? _fixtureInstructions(exercise.exerciseId)
              : '',
          exercise: exercise,
        ),
    ];
  }

  String _fixtureName(String exerciseId) {
    try {
      return exerciseDisplay(exerciseId: exerciseId).name;
    } on BridgeError {
      return 'This exercise could not be opened.';
    }
  }

  String _fixtureInstructions(String exerciseId) {
    try {
      return exerciseDisplay(exerciseId: exerciseId).writtenInstructions;
    } on BridgeError {
      return 'The exercise text could not be opened.';
    }
  }

  Future<void> _openSheet(_ShownExercise shown) async {
    final List<String> sentences = programReasonSentences(shown.exercise);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (BuildContext context) {
        final double height = MediaQuery.sizeOf(context).height * 0.9;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.space20),
              children: [
                Text(shown.instructions),
                const SizedBox(height: AppSpacing.space12),
                Text(programCounts(shown.exercise)),
                for (final String sentence in sentences) ...<Widget>[
                  const SizedBox(height: AppSpacing.space12),
                  Text(sentence),
                ],
                const SizedBox(height: AppSpacing.space24),
                SecondaryButton(
                  label: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _program == null
          ? null
          : AppBar(title: const Text('Your starting plan')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_storageFailed) {
      return const SizedBox.shrink();
    }
    if (!_ready) {
      return const Center(child: Text('Loading starting plan'));
    }
    if (_withheld || _program == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The synthetic rule did not produce a starting plan. Nothing was saved.',
          ),
          const SizedBox(height: AppSpacing.space24),
          PrimaryButton(label: 'Home', onPressed: () => context.go('/')),
        ],
      );
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(programNotice),
              const SizedBox(height: AppSpacing.space12),
              const Text(programSessionLine),
              const SizedBox(height: AppSpacing.space24),
              for (final _ShownExercise shown in _shown) ...<Widget>[
                _exerciseRow(shown),
                const SizedBox(height: AppSpacing.space24),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _exerciseRow(_ShownExercise shown) {
    final List<String> sentences = programReasonSentences(shown.exercise);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => unawaited(_openSheet(shown)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shown.name),
                const SizedBox(height: AppSpacing.space8),
                Text(programCounts(shown.exercise)),
              ],
            ),
          ),
        ),
        for (final String sentence in sentences) ...<Widget>[
          const SizedBox(height: AppSpacing.space12),
          Text(sentence),
        ],
      ],
    );
  }
}
