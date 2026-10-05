import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/workout/session_document.dart';

class ReadinessFlow extends StatefulWidget {
  const ReadinessFlow({super.key, required this.store});

  final ProfileStore store;

  @override
  State<ReadinessFlow> createState() => _ReadinessFlowState();
}

class _ReadinessFlowState extends State<ReadinessFlow> {
  var _open = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final bool terminal = await _hasCheckIn();
    if (!mounted) {
      return;
    }
    if (!terminal) {
      context.go('/');
      return;
    }
    setState(() {
      _open = true;
    });
  }

  Future<bool> _hasCheckIn() async {
    final StoredTerminalWorkout? terminal = await widget.store
        .loadNewestTerminalWorkout();
    if (terminal == null) {
      return false;
    }
    try {
      final LocalSession session = LocalSession.decode(terminal.documentJson);
      return session.outcome == 'completed' || session.outcome == 'abandoned';
    } on LocalSessionException {
      return false;
    }
  }

  Future<void> _submit(String soreness) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    final StoredTerminalWorkout? terminal = await widget.store
        .loadNewestTerminalWorkout();
    if (!mounted) {
      return;
    }
    if (terminal == null) {
      context.go('/');
      return;
    }
    final String intake = await widget.store.loadDraft() ?? '';
    final String assessment = await widget.store.loadAssessmentRecord() ?? '';
    final String program = await widget.store.loadProgramRecord() ?? '';
    final int recordedAtMs = widget.store.clockMillis();
    final String readiness = jsonEncode(<String, Object>{
      'record_version': 1,
      'recorded_at_ms': recordedAtMs,
      'rule_id': 'syn-adaptation-core',
      'rule_version': 1,
      'session_id': terminal.sessionId,
      'soreness': soreness,
    });
    final AdaptationView view = prepareAdaptation(
      intakeJson: intake,
      assessmentJson: assessment,
      programJson: program,
      workoutJson: terminal.documentJson,
      readinessJson: readiness,
    );
    if (!mounted) {
      return;
    }
    if (view.outcome == 'ready') {
      await widget.store.saveAdaptationPair(
        sessionId: terminal.sessionId,
        readinessJson: readiness,
        adaptationJson: view.documentJson,
        updatedAtMs: recordedAtMs,
      );
      if (!mounted) {
        return;
      }
      context.go('/');
      return;
    }
    context.go('/?adaptation=withheld');
  }

  Widget _choices() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PrimaryButton(
                  label: 'Low soreness',
                  onPressed: _busy ? null : () => _submit('low'),
                ),
                const SizedBox(height: AppSpacing.space24),
                PrimaryButton(
                  label: 'Moderate soreness',
                  onPressed: _busy ? null : () => _submit('moderate'),
                ),
                const SizedBox(height: AppSpacing.space24),
                PrimaryButton(
                  label: 'High soreness',
                  onPressed: _busy ? null : () => _submit('high'),
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: _open ? _choices() : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
