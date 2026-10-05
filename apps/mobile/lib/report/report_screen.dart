import 'dart:async';

import 'package:drift/isolate.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';

const List<(String, String)> _reportCategories = <(String, String)>[
  ('App issue', 'app_issue'),
  ('Exercise instruction', 'exercise_instruction'),
  ('Program feels wrong', 'program_feels_wrong'),
  ('Safety concern', 'safety_concern'),
  ('Content issue', 'content_issue'),
];

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.store, this.sessionId});

  final ProfileStore store;
  final String? sessionId;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final TextEditingController _note = TextEditingController();
  var _storageFailed = false;
  var _saving = false;
  var _sessionChecked = false;
  var _sessionStored = false;
  String? _category;
  StoredProblemReport? _report;

  @override
  void initState() {
    super.initState();
    final String? sessionId = widget.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      _sessionChecked = true;
      return;
    }
    unawaited(_checkSession(sessionId));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _checkSession(String sessionId) async {
    try {
      final bool stored = await widget.store.hasWorkoutRecord(sessionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _sessionChecked = true;
        _sessionStored = stored;
      });
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

  Future<void> _save() async {
    final String? category = _category;
    if (_saving || _storageFailed || category == null) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      String? sessionId;
      final String? requested = widget.sessionId;
      if (requested != null && requested.isNotEmpty) {
        final bool stored = _sessionChecked
            ? _sessionStored
            : await widget.store.hasWorkoutRecord(requested);
        if (!mounted || _storageFailed) {
          return;
        }
        if (stored) {
          sessionId = requested;
        }
      }
      final String reportId = await widget.store.saveProblemReport(
        category: category,
        note: _note.text,
        sessionId: sessionId,
      );
      final StoredProblemReport? report = await widget.store.loadProblemReport(
        reportId,
      );
      if (!mounted) {
        return;
      }
      if (report == null) {
        _failStorage();
        return;
      }
      setState(() {
        _report = report;
      });
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
    } finally {
      _saving = false;
    }
  }

  void _failStorage() {
    if (!mounted) {
      return;
    }
    setState(() {
      _storageFailed = true;
      _report = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.go('/storage-failure');
    });
  }

  void _choose(String token) {
    if (_saving || _storageFailed) {
      return;
    }
    setState(() {
      _category = token;
    });
  }

  Widget _choiceRow(String token, String label) {
    return Row(
      children: [
        Radio<String>(value: token),
        Expanded(
          child: GestureDetector(
            onTap: () {
              _choose(token);
            },
            child: Text(label),
          ),
        ),
      ],
    );
  }

  String _categoryLabel(String token) {
    for (final (String label, String value) in _reportCategories) {
      if (value == token) {
        return label;
      }
    }
    return token;
  }

  Widget _form() {
    final String? category = _category;
    final bool clinician =
        category == 'program_feels_wrong' || category == 'safety_concern';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Report a problem'),
        const SizedBox(height: AppSpacing.space24),
        const Text('This report stays on this device.'),
        const SizedBox(height: AppSpacing.space24),
        const Text('The profile database is encrypted.'),
        const SizedBox(height: AppSpacing.space24),
        const Text('Nothing is sent off this device.'),
        const SizedBox(height: AppSpacing.space24),
        const Text('No clinician is contacted.'),
        if (_sessionChecked &&
            !_sessionStored &&
            widget.sessionId != null &&
            widget.sessionId!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.space24),
          const Text('The saved session could not be attached.'),
        ],
        const SizedBox(height: AppSpacing.space24),
        const Text('Category'),
        const SizedBox(height: AppSpacing.space24),
        RadioGroup<String>(
          groupValue: category,
          onChanged: (String? value) {
            if (value == null) {
              return;
            }
            _choose(value);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final (String label, String token) in _reportCategories)
                _choiceRow(token, label),
            ],
          ),
        ),
        if (clinician) ...<Widget>[
          const SizedBox(height: AppSpacing.space24),
          const Text('This does not contact a clinician.'),
        ],
        const SizedBox(height: AppSpacing.space24),
        const Text('Note'),
        TextField(controller: _note, maxLength: 500),
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(
          label: 'Save',
          onPressed: category == null || _saving
              ? null
              : () {
                  unawaited(_save());
                },
        ),
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(label: 'Back', onPressed: () => context.go('/')),
      ],
    );
  }

  Widget _readout(StoredProblemReport report) {
    final bool programAttached =
        report.programRuleId != null &&
        report.programRuleVersion != null &&
        report.safetyRuleId != null &&
        report.safetyRuleVersion != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Text('Saved on this device.'),
        const SizedBox(height: AppSpacing.space24),
        Text(_categoryLabel(report.category)),
        const SizedBox(height: AppSpacing.space24),
        if (programAttached) ...<Widget>[
          Text(
            'Program rule ${report.programRuleId} ${report.programRuleVersion}.',
          ),
          const SizedBox(height: AppSpacing.space24),
          Text(
            'Safety rule ${report.safetyRuleId} ${report.safetyRuleVersion}.',
          ),
        ] else
          const Text('No stored program was attached.'),
        const SizedBox(height: AppSpacing.space24),
        if (report.sessionId != null)
          Text('Session ${report.sessionId}.')
        else
          const Text('No saved session was attached.'),
        const SizedBox(height: AppSpacing.space24),
        Text('Report ${report.reportId}.'),
        if (report.note.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.space24),
          Text(report.note),
        ],
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(label: 'Back', onPressed: () => context.go('/')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final StoredProblemReport? report = _report;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    minHeight: constraints.maxHeight,
                  ),
                  child: _storageFailed
                      ? const SizedBox.shrink()
                      : report == null
                      ? _form()
                      : _readout(report),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
