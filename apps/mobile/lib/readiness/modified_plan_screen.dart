import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/readiness/adaptation_document.dart';
import 'package:helpmemove/storage/profile_store.dart';

class ModifiedPlanScreen extends StatefulWidget {
  const ModifiedPlanScreen({super.key, this.store, this.previewDocument});

  final ProfileStore? store;
  final String? previewDocument;

  @override
  State<ModifiedPlanScreen> createState() => _ModifiedPlanScreenState();
}

class _ModifiedPlanScreenState extends State<ModifiedPlanScreen> {
  StoredAdaptation? _decision;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final String? preview = widget.previewDocument;
    StoredAdaptation? decision;
    if (preview != null) {
      try {
        decision = StoredAdaptation.decode(preview);
      } on AdaptationDocumentException {
        decision = null;
      }
    } else {
      final ProfileStore? store = widget.store;
      if (store != null) {
        final StoredTerminalWorkout? terminal = await store
            .loadNewestTerminalWorkout();
        if (terminal != null) {
          final String? raw = await store.loadAdaptationRecord(
            terminal.sessionId,
          );
          if (raw != null) {
            try {
              final StoredAdaptation decoded = StoredAdaptation.decode(raw);
              if (decoded.sessionId == terminal.sessionId) {
                decision = decoded;
              }
            } on AdaptationDocumentException {
              decision = null;
            }
          }
        }
      }
    }
    if (!mounted) {
      return;
    }
    if (decision == null) {
      context.go('/');
      return;
    }
    setState(() {
      _decision = decision;
    });
  }

  @override
  Widget build(BuildContext context) {
    final StoredAdaptation? decision = _decision;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: decision == null
              ? const SizedBox.shrink()
              : LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(decision.reason),
                            const SizedBox(height: AppSpacing.space24),
                            if (decision.action == 'maintain') ...[
                              PrimaryButton(
                                label: 'Start workout',
                                onPressed: () => context.go('/focus/workout'),
                              ),
                              const SizedBox(height: AppSpacing.space24),
                            ],
                            PrimaryButton(
                              label: 'Back',
                              onPressed: () => context.go('/'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
