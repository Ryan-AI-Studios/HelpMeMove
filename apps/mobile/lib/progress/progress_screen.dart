import 'dart:async';
import 'dart:convert';

import 'package:drift/isolate.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/readiness/adaptation_document.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.store});

  final ProfileStore store;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  var _ready = false;
  var _unreadable = false;
  var _storageFailed = false;
  StoredProgressSummary? _summary;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<StoredTerminalWorkout> rows = await widget.store
          .loadWorkoutRecords();
      final String entries = jsonEncode(<Object>[
        for (final StoredTerminalWorkout row in rows)
          <String, Object>{
            'document_json': row.documentJson,
            'session_id': row.sessionId,
            'updated_at_ms': row.updatedAtMs,
          },
      ]);
      final ProgressView view = prepareProgressSummary(entriesJson: entries);
      if (!mounted) {
        return;
      }
      if (view.outcome != 'ready') {
        setState(() {
          _ready = true;
          _unreadable = true;
          _summary = null;
        });
        return;
      }
      try {
        final StoredProgressSummary decoded = StoredProgressSummary.decode(
          view.documentJson,
        );
        setState(() {
          _ready = true;
          _unreadable = false;
          _summary = decoded;
        });
      } on AdaptationDocumentException {
        setState(() {
          _ready = true;
          _unreadable = true;
          _summary = null;
        });
      }
    } on StorageKeyLoss {
      _failStorage();
    } on StorageCipherUnavailable {
      _failStorage();
    } on StorageSchemaException {
      _failStorage();
    } on StorageIoException {
      _failStorage();
    } on SqliteException {
      _failStorage();
    } on DriftRemoteException {
      _failStorage();
    }
  }

  void _failStorage() {
    if (!mounted) {
      return;
    }
    setState(() {
      _ready = true;
      _storageFailed = true;
      _unreadable = false;
      _summary = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.go('/storage-failure');
    });
  }

  Widget _lines(StoredProgressSummary summary) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Local progress'),
        const SizedBox(height: AppSpacing.space24),
        Text('Completed sessions: ${summary.completedCount}'),
        const SizedBox(height: AppSpacing.space24),
        Text('Abandoned sessions: ${summary.abandonedCount}'),
        const SizedBox(height: AppSpacing.space24),
        Text('Safety stops: ${summary.safetyStoppedCount}'),
        if (summary.completedCount >= 1) ...[
          const SizedBox(height: AppSpacing.space24),
          const Text('A stored session is on this device.'),
        ],
        if (summary.copiedPain != null) ...[
          const SizedBox(height: AppSpacing.space24),
          Text('Last stored pain: ${summary.copiedPain}'),
        ],
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(label: 'Back', onPressed: () => context.go('/')),
      ],
    );
  }

  Widget _message(String sentence) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(sentence),
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(label: 'Back', onPressed: () => context.go('/')),
      ],
    );
  }

  Widget _body() {
    if (_storageFailed) {
      return const SizedBox.shrink();
    }
    final StoredProgressSummary? summary = _summary;
    if (_unreadable || summary == null) {
      return _message('The saved sessions could not be read.');
    }
    if (summary.countsAreZero) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Local progress'),
          const SizedBox(height: AppSpacing.space24),
          const Text('No stored session yet.'),
          const SizedBox(height: AppSpacing.space24),
          PrimaryButton(label: 'Back', onPressed: () => context.go('/')),
        ],
      );
    }
    return _lines(summary);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: _ready
              ? LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                          minHeight: constraints.maxHeight,
                        ),
                        child: _body(),
                      ),
                    );
                  },
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
