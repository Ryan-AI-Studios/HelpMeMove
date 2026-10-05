import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/readiness/adaptation_document.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/workout/session_document.dart';

class FlareFollowupFlow extends StatefulWidget {
  const FlareFollowupFlow({super.key, required this.store});

  final ProfileStore store;

  @override
  State<FlareFollowupFlow> createState() => _FlareFollowupFlowState();
}

class _FlareFollowupFlowState extends State<FlareFollowupFlow> {
  var _open = false;
  var _busy = false;
  StoredFlareFollowup? _saved;

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

  Future<void> _submit(String choice) async {
    if (_busy || _saved != null) {
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
    final String followup = jsonEncode(<String, Object>{
      'record_version': 1,
      'recorded_at_ms': recordedAtMs,
      'rule_id': 'syn-flare-core',
      'rule_version': 1,
      'session_id': terminal.sessionId,
      'choice': choice,
    });
    final FlareView view = prepareFlareFollowup(
      intakeJson: intake,
      assessmentJson: assessment,
      programJson: program,
      workoutJson: terminal.documentJson,
      followupJson: followup,
    );
    if (!mounted) {
      return;
    }
    if (view.outcome == 'ready') {
      final String? existing = await widget.store.loadFlareFollowup(
        terminal.sessionId,
      );
      if (existing == null) {
        await widget.store.saveFlareFollowup(
          sessionId: terminal.sessionId,
          documentJson: view.documentJson,
          updatedAtMs: recordedAtMs,
        );
      }
      final String stored =
          await widget.store.loadFlareFollowup(terminal.sessionId) ??
          view.documentJson;
      if (!mounted) {
        return;
      }
      try {
        final StoredFlareFollowup decoded = StoredFlareFollowup.decode(stored);
        setState(() {
          _saved = decoded;
          _busy = false;
        });
      } on AdaptationDocumentException {
        setState(() {
          _busy = false;
        });
      }
      return;
    }
    context.go('/?flare=withheld');
  }

  Widget _body() {
    final StoredFlareFollowup? saved = _saved;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (saved == null) ...[
                  PrimaryButton(
                    label: 'Worse today',
                    onPressed: _busy ? null : () => _submit('worse_today'),
                  ),
                  const SizedBox(height: AppSpacing.space24),
                  PrimaryButton(
                    label: 'About the same',
                    onPressed: _busy ? null : () => _submit('same'),
                  ),
                  const SizedBox(height: AppSpacing.space24),
                  PrimaryButton(
                    label: 'Settled',
                    onPressed: _busy ? null : () => _submit('settled'),
                  ),
                ] else ...[
                  Text(saved.reason),
                  const SizedBox(height: AppSpacing.space24),
                  if (saved.action == 'keep_program') ...[
                    PrimaryButton(
                      label: 'Start workout',
                      onPressed: () => context.go('/focus/workout'),
                    ),
                    const SizedBox(height: AppSpacing.space24),
                  ],
                ],
                PrimaryButton(label: 'Back', onPressed: () => context.go('/')),
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
          child: _open ? _body() : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
