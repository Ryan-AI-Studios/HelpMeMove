import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:helpmemove/program/program_document.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/encryption.dart';
import 'package:helpmemove/storage/profile_database.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';

class StoredTerminalWorkout {
  const StoredTerminalWorkout({
    required this.sessionId,
    required this.documentJson,
    required this.updatedAtMs,
  });

  final String sessionId;
  final String documentJson;
  final int updatedAtMs;
}

class SyncOutboxPendingItem {
  const SyncOutboxPendingItem({
    required this.eventId,
    required this.entity,
    required this.localKey,
    required this.documentSha256,
    required this.documentJson,
  });

  final String eventId;
  final String entity;
  final String localKey;
  final String documentSha256;
  final String documentJson;
}

class StoredProblemReport {
  const StoredProblemReport({
    required this.reportId,
    required this.category,
    required this.note,
    required this.programRecordVersion,
    required this.programRuleId,
    required this.programRuleVersion,
    required this.safetyRuleId,
    required this.safetyRuleVersion,
    required this.exerciseId,
    required this.exerciseVersion,
    required this.sessionId,
    required this.createdAtMs,
  });

  final String reportId;
  final String category;
  final String note;
  final int? programRecordVersion;
  final String? programRuleId;
  final int? programRuleVersion;
  final String? safetyRuleId;
  final int? safetyRuleVersion;
  final String? exerciseId;
  final int? exerciseVersion;
  final String? sessionId;
  final int createdAtMs;
}

const String activeProfileItem = 'active-profile';
const String copyAcceptedName = 'sync-copy-accepted';
const String _exportFileName = 'export.json';

enum LocalRemoval { directoryRemained, replaced, notReplaced }

const String _profileKeyPrefix = 'profile-key.';
const String _programOutboxEntity = 'program_records';
const String _workoutOutboxEntity = 'workout_records';
const String _outboxPending = 'pending';
const String _outboxConfirmed = 'confirmed';
const String _outboxRejected = 'rejected';

String profileKeyItem(String subjectId) => '$_profileKeyPrefix$subjectId';

class ProfileStore {
  ProfileStore({
    required this.keys,
    required this.supportDirectory,
    required this.clock,
    required this.random,
    required this.excludeFromBackup,
  });

  final ProfileKeyStore keys;
  final Directory supportDirectory;
  final DateTime Function() clock;
  final Random random;
  final Future<void> Function(String path) excludeFromBackup;

  void Function()? onOutboxEnqueued;

  ProfileDatabase? _database;
  Completer<void>? _workoutTurn;

  /// Tests override this to occupy the workout write queue.
  Future<void> onWorkoutQueueEntered() async {}

  /// Tests throw from here to prove a checkpoint error still closes the file.
  Future<void> Function()? onBeforeCheckpoint;

  /// Tests record when a profile file begins to open.
  void Function()? onOpenStarted;

  /// Tests record when a database connection has finished closing.
  void Function()? onDatabaseClosed;

  /// Tests throw from here before the subject directory is deleted.
  Future<void> Function()? onBeforeDirectoryDelete;

  /// Tests throw from here before `export.json` is written.
  Future<void> Function(File file)? onBeforeExportWrite;

  /// Tests throw from here after `export.json` exists and before backup exclusion.
  Future<void> Function()? onExportFileCreated;

  int _unpublishedOpens = 0;

  /// Connections created but not yet published or closed.
  int get unpublishedOpens => _unpublishedOpens;

  Future<void>? _lifecycleQueue;

  Future<T> _lifecycle<T>(Future<T> Function() action) async {
    if (Zone.current[#helpmemoveProfileLifecycle] == true) {
      return action();
    }
    final Completer<void> turn = Completer<void>();
    final Future<void>? earlier = _lifecycleQueue;
    _lifecycleQueue = turn.future;
    if (earlier != null) {
      await earlier;
    }
    try {
      return await runZoned(
        action,
        zoneValues: <Object?, Object?>{#helpmemoveProfileLifecycle: true},
      );
    } finally {
      turn.complete();
    }
  }

  Future<T> _queuedWorkout<T>(Future<T> Function() action) async {
    final Completer<void> turn = Completer<void>();
    final Future<void>? earlier = _workoutTurn?.future;
    _workoutTurn = turn;
    if (earlier != null) {
      await earlier;
    }
    try {
      return await action();
    } finally {
      if (identical(_workoutTurn, turn)) {
        _workoutTurn = null;
      }
      turn.complete();
    }
  }

  Future<String> openActive() => _lifecycle(_openActive);

  Future<String> _openActive() async {
    String? accepted;
    try {
      final String? active = await keys.read(activeProfileItem);
      if (active == null || active.isEmpty) {
        await createProfile();
        return '/';
      }
      accepted = acceptSubject(raw: active);
      final String? keyHex = await keys.read(profileKeyItem(accepted));
      if (keyHex == null) {
        await _closeCurrent();
        await _deleteExportQuiet(accepted);
        return '/key-loss';
      }
      await _closeCurrent();
      await _openExisting(accepted, keyHex);
      await _deleteExportQuiet(accepted);
      return '/';
    } on StorageKeyLoss {
      await _deleteExportQuiet(accepted);
      return '/key-loss';
    } on StorageCipherUnavailable {
      await _deleteExportQuiet(accepted);
      return '/storage-failure';
    } on StorageSchemaException {
      await _deleteExportQuiet(accepted);
      return '/storage-failure';
    } on StorageIoException {
      await _deleteExportQuiet(accepted);
      return '/storage-failure';
    } on SqliteException {
      await _deleteExportQuiet(accepted);
      return '/storage-failure';
    } on FileSystemException {
      await _deleteExportQuiet(accepted);
      return '/storage-failure';
    }
  }

  Future<void> _deleteExportQuiet(String? subjectId) async {
    if (subjectId == null) {
      return;
    }
    try {
      await deleteExport(subjectId);
    } on Object {
      // A thrown delete must not change the route openActive returns.
    }
  }

  Future<String> createProfile() => _lifecycle(_createProfile);

  Future<String> _createProfile() async {
    await _closeCurrent();
    final String subjectId = _newSubjectId();
    final String keyHex = _newKeyHex();
    await keys.write(profileKeyItem(subjectId), keyHex);
    await _openExisting(subjectId, keyHex);
    await keys.write(activeProfileItem, subjectId);
    return subjectId;
  }

  Future<void> switchTo(String raw, {bool Function()? stillCurrent}) {
    return _lifecycle(() => _switchTo(raw, stillCurrent: stillCurrent));
  }

  Future<void> _switchTo(String raw, {bool Function()? stillCurrent}) async {
    final String subjectId = acceptSubject(raw: raw);
    final String? keyHex = await keys.read(profileKeyItem(subjectId));
    if (stillCurrent != null && !stillCurrent()) {
      return;
    }
    if (keyHex == null) {
      throw const StorageKeyLoss();
    }
    await _closeCurrent();
    if (stillCurrent != null && !stillCurrent()) {
      return;
    }
    await _openExisting(subjectId, keyHex);
    if (stillCurrent != null && !stillCurrent()) {
      await _closeCurrent();
      return;
    }
    await keys.write(activeProfileItem, subjectId);
  }

  Future<String> resetActive() => _lifecycle(_resetActive);

  Future<String> _resetActive() async {
    final String? active = await keys.read(activeProfileItem);
    await _closeCurrent();
    if (active != null && active.isNotEmpty) {
      await keys.delete(profileKeyItem(active));
      final Directory directory = _profileDirectory(active);
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
    await keys.delete(activeProfileItem);
    await createProfile();
    return '/';
  }

  Future<void> checkpoint() async {
    await _requireDatabase().checkpoint();
  }

  Future<void> close() => _lifecycle(_closeCurrent);

  String? get activeSubjectId => _activeSubjectId;

  bool get hasOpenDatabase => _database != null;

  bool isCopyAccepted(String subjectId) {
    return _copyAcceptedFile(subjectId).existsSync();
  }

  Future<void> markCopyAccepted(String subjectId) async {
    final Directory directory = _profileDirectory(subjectId);
    directory.createSync(recursive: true);
    _copyAcceptedFile(subjectId).writeAsBytesSync(const <int>[]);
    await excludeFromBackup(directory.path);
  }

  Future<List<SyncOutboxPendingItem>> loadPendingOutbox(
    String subjectId,
  ) async {
    final ProfileDatabase database = _requireDatabase();
    final List<SyncOutboxData> rows =
        await (database.select(database.syncOutbox)..where(
              (SyncOutbox table) =>
                  table.subjectId.equals(subjectId) &
                  table.state.equals(_outboxPending),
            ))
            .get();
    final List<SyncOutboxPendingItem> items = <SyncOutboxPendingItem>[];
    for (final SyncOutboxData row in rows) {
      final String? documentJson = await _outboxDocumentJson(
        database,
        subjectId,
        row.entity,
        row.localKey,
      );
      if (documentJson == null) {
        continue;
      }
      items.add(
        SyncOutboxPendingItem(
          eventId: row.eventId,
          entity: row.entity,
          localKey: row.localKey,
          documentSha256: row.documentSha256,
          documentJson: documentJson,
        ),
      );
    }
    return items;
  }

  Future<void> markOutboxState({
    required String subjectId,
    required String eventId,
    required String expectedSha,
    required String state,
  }) async {
    if (state != _outboxConfirmed && state != _outboxRejected) {
      return;
    }
    final ProfileDatabase database = _requireDatabase();
    await (database.update(database.syncOutbox)..where(
          (SyncOutbox table) =>
              table.subjectId.equals(subjectId) &
              table.eventId.equals(eventId) &
              table.documentSha256.equals(expectedSha),
        ))
        .write(
          SyncOutboxCompanion(
            state: Value<String>(state),
            updatedAtMs: Value<int>(_now()),
          ),
        );
  }

  Future<void> sweepCopyOutbox() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await database.transaction(() async {
      final List<ProgramRecord> programs =
          await (database.select(database.programRecords)..where(
                (ProgramRecords table) => table.subjectId.equals(subjectId),
              ))
              .get();
      for (final ProgramRecord program in programs) {
        await _upsertProgramOutbox(database, subjectId, program.documentJson);
      }
      final List<WorkoutRecord> workouts =
          await (database.select(database.workoutRecords)..where(
                (WorkoutRecords table) => table.subjectId.equals(subjectId),
              ))
              .get();
      for (final WorkoutRecord workout in workouts) {
        final SyncOutboxData? existing = await _outboxRow(
          database,
          subjectId,
          _workoutOutboxEntity,
          workout.sessionId,
        );
        if (existing == null) {
          await _insertPendingOutbox(
            database,
            subjectId: subjectId,
            entity: _workoutOutboxEntity,
            localKey: workout.sessionId,
            documentJson: workout.documentJson,
          );
        }
      }
    });
  }

  /// Closes the open database and clears the active pointer.
  /// The profile key and files stay on disk.
  Future<void> lockOpenProfile() => _lifecycle(_lockOpenProfile);

  Future<void> _lockOpenProfile() async {
    await _closeCurrent();
    await keys.delete(activeProfileItem);
  }

  /// Deletes one subject's key and directory. Other subjects stay.
  Future<void> deleteSubjectFiles(String raw) {
    return _lifecycle(() => _deleteSubjectFiles(raw));
  }

  Future<void> _deleteSubjectFiles(String raw) async {
    final String subjectId = acceptSubject(raw: raw);
    if (_activeSubjectId == subjectId) {
      await _closeCurrent();
    }
    await keys.delete(profileKeyItem(subjectId));
    final Directory directory = _profileDirectory(subjectId);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
    final String? active = await keys.read(activeProfileItem);
    if (active == subjectId) {
      await keys.delete(activeProfileItem);
    }
  }

  Future<void> writeExport() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final List<Map<String, Object>> records = <Map<String, Object>>[];
    await database.transaction(() async {
      final LocalProfile? profile =
          await (database.select(database.localProfiles)..where(
                (LocalProfiles table) => table.subjectId.equals(subjectId),
              ))
              .getSingleOrNull();
      if (profile != null) {
        records.add(<String, Object>{
          'table': 'local_profiles',
          'subject_id': profile.subjectId,
          'created_at_ms': profile.createdAtMs,
          'last_active_at_ms': profile.lastActiveAtMs,
        });
      }
      final AssessmentRecord? assessment =
          await (database.select(database.assessmentRecords)..where(
                (AssessmentRecords table) => table.subjectId.equals(subjectId),
              ))
              .getSingleOrNull();
      if (assessment != null) {
        records.add(<String, Object>{
          'table': 'assessment_records',
          'updated_at_ms': assessment.updatedAtMs,
          'document_json': assessment.documentJson,
        });
      }
      final ProgramRecord? program =
          await (database.select(database.programRecords)..where(
                (ProgramRecords table) => table.subjectId.equals(subjectId),
              ))
              .getSingleOrNull();
      if (program != null) {
        records.add(<String, Object>{
          'table': 'program_records',
          'updated_at_ms': program.updatedAtMs,
          'document_json': program.documentJson,
        });
      }
      final List<WorkoutRecord> workouts =
          await (database.select(database.workoutRecords)
                ..where(
                  (WorkoutRecords table) => table.subjectId.equals(subjectId),
                )
                ..orderBy(<OrderClauseGenerator<WorkoutRecords>>[
                  (WorkoutRecords table) => OrderingTerm(
                    expression: table.updatedAtMs,
                    mode: OrderingMode.asc,
                  ),
                  (WorkoutRecords table) => OrderingTerm(
                    expression: table.sessionId,
                    mode: OrderingMode.asc,
                  ),
                ]))
              .get();
      for (final WorkoutRecord workout in workouts) {
        records.add(<String, Object>{
          'table': 'workout_records',
          'session_id': workout.sessionId,
          'updated_at_ms': workout.updatedAtMs,
          'document_json': workout.documentJson,
        });
      }
    });
    final String encoded = jsonEncode(<String, Object>{
      'subject_id': subjectId,
      'records': records,
    });
    final Directory directory = _profileDirectory(subjectId);
    final File file = _exportFile(subjectId);
    var created = false;
    try {
      directory.createSync(recursive: true);
      final Future<void> Function(File file)? beforeWrite = onBeforeExportWrite;
      if (beforeWrite != null) {
        await beforeWrite(file);
      }
      file.writeAsStringSync(encoded, flush: true);
      created = true;
      final Future<void> Function()? afterCreate = onExportFileCreated;
      if (afterCreate != null) {
        await afterCreate();
      }
      await excludeFromBackup(directory.path);
    } on Object catch (error, stackTrace) {
      if (created || file.existsSync()) {
        _deleteExportFileSync(file);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> deleteExport([String? subjectId]) async {
    try {
      final String? target = subjectId ?? _activeSubjectId;
      if (target == null) {
        return;
      }
      final String safeTarget = acceptSubject(raw: target);
      _deleteExportFileSync(_exportFile(safeTarget));
    } on Object {
      // A missing file or another file error completes without an error.
    }
  }

  Future<LocalRemoval> removeSubjectDirectoryFirst(String subjectId) async {
    final String safeSubject = acceptSubject(raw: subjectId);
    final bool wasActive = safeSubject == _activeSubjectId;
    if (wasActive) {
      await _closeCurrent();
    }
    final Directory directory = _profileDirectory(safeSubject);
    try {
      final Future<void> Function()? beforeDelete = onBeforeDirectoryDelete;
      if (beforeDelete != null) {
        await beforeDelete();
      }
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    } on Object {
      if (wasActive) {
        try {
          await reopenActive();
        } on Object {
          return LocalRemoval.directoryRemained;
        }
      }
      return LocalRemoval.directoryRemained;
    }
    try {
      await keys.delete(profileKeyItem(safeSubject));
    } on Object {
      // The directory is already gone. Still replace the profile.
    }
    try {
      final String? active = await keys.read(activeProfileItem);
      if (active == safeSubject) {
        await keys.delete(activeProfileItem);
      }
    } on Object {
      // The directory is already gone. Still replace the profile.
    }
    try {
      await createProfile();
      return LocalRemoval.replaced;
    } on Object {
      return LocalRemoval.notReplaced;
    }
  }

  File _exportFile(String subjectId) {
    return File(
      '${_profileDirectory(subjectId).path}${Platform.pathSeparator}$_exportFileName',
    );
  }

  void _deleteExportFileSync(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on Object {
      // The caller still reports the original failure.
    }
  }

  Future<void> saveDraft(String documentJson) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await database
        .into(database.intakeDrafts)
        .insertOnConflictUpdate(
          IntakeDraftsCompanion.insert(
            subjectId: subjectId,
            documentJson: documentJson,
            updatedAtMs: _now(),
          ),
        );
  }

  Future<String?> loadDraft() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final IntakeDraft? row =
        await (database.select(
              database.intakeDrafts,
            )..where((IntakeDrafts table) => table.subjectId.equals(subjectId)))
            .getSingleOrNull();
    return row?.documentJson;
  }

  Future<void> deleteDraft() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await (database.delete(
      database.intakeDrafts,
    )..where((IntakeDrafts table) => table.subjectId.equals(subjectId))).go();
  }

  Future<void> saveAssessmentDraft(String documentJson) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await database
        .into(database.assessmentDrafts)
        .insertOnConflictUpdate(
          AssessmentDraftsCompanion.insert(
            subjectId: subjectId,
            documentJson: documentJson,
            updatedAtMs: _now(),
          ),
        );
  }

  Future<String?> loadAssessmentDraft() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final AssessmentDraft? row =
        await (database.select(database.assessmentDrafts)..where(
              (AssessmentDrafts table) => table.subjectId.equals(subjectId),
            ))
            .getSingleOrNull();
    return row?.documentJson;
  }

  Future<void> deleteAssessmentDraft() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await (database.delete(
          database.assessmentDrafts,
        )..where((AssessmentDrafts table) => table.subjectId.equals(subjectId)))
        .go();
  }

  Future<void> saveAssessmentRecord(String documentJson) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await database
        .into(database.assessmentRecords)
        .insertOnConflictUpdate(
          AssessmentRecordsCompanion.insert(
            subjectId: subjectId,
            documentJson: documentJson,
            updatedAtMs: _now(),
          ),
        );
  }

  Future<String?> loadAssessmentRecord() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final AssessmentRecord? row =
        await (database.select(database.assessmentRecords)..where(
              (AssessmentRecords table) => table.subjectId.equals(subjectId),
            ))
            .getSingleOrNull();
    return row?.documentJson;
  }

  Future<void> deleteAssessmentRecord() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await (database.delete(database.assessmentRecords)..where(
          (AssessmentRecords table) => table.subjectId.equals(subjectId),
        ))
        .go();
  }

  Future<void> saveProgramRecord(String documentJson) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    var outboxChanged = false;
    await database.transaction(() async {
      await database
          .into(database.programRecords)
          .insertOnConflictUpdate(
            ProgramRecordsCompanion.insert(
              subjectId: subjectId,
              documentJson: documentJson,
              updatedAtMs: _now(),
            ),
          );
      if (await _shouldEnqueueOutbox(database, subjectId)) {
        outboxChanged = await _upsertProgramOutbox(
          database,
          subjectId,
          documentJson,
        );
      }
    });
    if (outboxChanged) {
      onOutboxEnqueued?.call();
    }
  }

  Future<String?> loadProgramRecord() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final ProgramRecord? row =
        await (database.select(database.programRecords)..where(
              (ProgramRecords table) => table.subjectId.equals(subjectId),
            ))
            .getSingleOrNull();
    return row?.documentJson;
  }

  Future<void> deleteProgramRecord() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await (database.delete(
      database.programRecords,
    )..where((ProgramRecords table) => table.subjectId.equals(subjectId))).go();
  }

  /// Store-generated session id. The client does not supply it.
  String newSessionId() => _newEventId();

  Future<void> saveWorkoutDraft(String documentJson) {
    return _queuedWorkout(() => _saveWorkoutDraftNow(documentJson));
  }

  Future<void> _saveWorkoutDraftNow(String documentJson) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final String? sessionId = _sessionIdIn(documentJson);
    if (sessionId != null && await _workoutRecordExists(subjectId, sessionId)) {
      return;
    }
    await database
        .into(database.workoutDrafts)
        .insertOnConflictUpdate(
          WorkoutDraftsCompanion.insert(
            subjectId: subjectId,
            documentJson: documentJson,
            updatedAtMs: _now(),
          ),
        );
  }

  Future<String?> loadWorkoutDraft() {
    return _queuedWorkout(_loadWorkoutDraftNow);
  }

  Future<String?> _loadWorkoutDraftNow() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final WorkoutDraft? row =
        await (database.select(database.workoutDrafts)..where(
              (WorkoutDrafts table) => table.subjectId.equals(subjectId),
            ))
            .getSingleOrNull();
    final String? documentJson = row?.documentJson;
    if (documentJson == null) {
      return null;
    }
    final String? sessionId = _sessionIdIn(documentJson);
    if (sessionId != null && await _workoutRecordExists(subjectId, sessionId)) {
      await _deleteWorkoutDraftNow(subjectId);
      return null;
    }
    return documentJson;
  }

  Future<void> deleteWorkoutDraft() {
    return _queuedWorkout(() => _deleteWorkoutDraftNow(_requireActive()));
  }

  Future<void> _deleteWorkoutDraftNow(String subjectId) async {
    final ProfileDatabase database = _requireDatabase();
    await (database.delete(
      database.workoutDrafts,
    )..where((WorkoutDrafts table) => table.subjectId.equals(subjectId))).go();
  }

  Future<void> saveWorkoutTerminal({
    required String sessionId,
    required String documentJson,
  }) {
    return _queuedWorkout(() async {
      await onWorkoutQueueEntered();
      final ProfileDatabase database = _requireDatabase();
      final String subjectId = _requireActive();
      var outboxInserted = false;
      await database.transaction(() async {
        await database
            .into(database.workoutRecords)
            .insert(
              WorkoutRecordsCompanion.insert(
                subjectId: subjectId,
                sessionId: sessionId,
                documentJson: documentJson,
                updatedAtMs: _now(),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        await _deleteWorkoutDraftNow(subjectId);
        if (await _shouldEnqueueOutbox(database, subjectId)) {
          outboxInserted = await _insertMissingWorkoutOutbox(
            database,
            subjectId,
            sessionId,
            documentJson,
          );
        }
      });
      if (outboxInserted) {
        onOutboxEnqueued?.call();
      }
    });
  }

  Future<bool> _workoutRecordExists(String subjectId, String sessionId) async {
    final ProfileDatabase database = _requireDatabase();
    final WorkoutRecord? row =
        await (database.select(database.workoutRecords)..where(
              (WorkoutRecords table) =>
                  table.subjectId.equals(subjectId) &
                  table.sessionId.equals(sessionId),
            ))
            .getSingleOrNull();
    return row != null;
  }

  String? _sessionIdIn(String documentJson) {
    try {
      final Object? decoded = jsonDecode(documentJson);
      if (decoded is! Map) {
        return null;
      }
      final Object? sessionId = decoded['session_id'];
      if (sessionId is String && sessionId.isNotEmpty) {
        return sessionId;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<List<String>> workoutRecordDocuments() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final List<WorkoutRecord> rows =
        await (database.select(database.workoutRecords)..where(
              (WorkoutRecords table) => table.subjectId.equals(subjectId),
            ))
            .get();
    return <String>[for (final WorkoutRecord row in rows) row.documentJson];
  }

  Future<int> workoutRecordCount() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final List<WorkoutRecord> rows =
        await (database.select(database.workoutRecords)..where(
              (WorkoutRecords table) => table.subjectId.equals(subjectId),
            ))
            .get();
    return rows.length;
  }

  Future<StoredTerminalWorkout?> loadNewestTerminalWorkout() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final WorkoutRecord? row =
        await (database.select(database.workoutRecords)
              ..where(
                (WorkoutRecords table) => table.subjectId.equals(subjectId),
              )
              ..orderBy(<OrderClauseGenerator<WorkoutRecords>>[
                (WorkoutRecords table) => OrderingTerm(
                  expression: table.updatedAtMs,
                  mode: OrderingMode.desc,
                ),
                (WorkoutRecords table) => OrderingTerm(
                  expression: table.sessionId,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return StoredTerminalWorkout(
      sessionId: row.sessionId,
      documentJson: row.documentJson,
      updatedAtMs: row.updatedAtMs,
    );
  }

  Future<List<StoredTerminalWorkout>> loadWorkoutRecords() async {
    try {
      final ProfileDatabase database = _requireDatabase();
      final String subjectId = _requireActive();
      final List<WorkoutRecord> rows =
          await (database.select(database.workoutRecords)..where(
                (WorkoutRecords table) => table.subjectId.equals(subjectId),
              ))
              .get();
      return <StoredTerminalWorkout>[
        for (final WorkoutRecord row in rows)
          StoredTerminalWorkout(
            sessionId: row.sessionId,
            documentJson: row.documentJson,
            updatedAtMs: row.updatedAtMs,
          ),
      ];
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_surfaceStorageError(error), stackTrace);
    }
  }

  Future<String?> loadAppearanceChoice() async {
    try {
      final String subjectId = _requireActive();
      final ProfileDatabase database = _requireDatabase();
      final AppearanceRecord? row =
          await (database.select(database.appearanceRecords)..where(
                (AppearanceRecords table) => table.subjectId.equals(subjectId),
              ))
              .getSingleOrNull();
      return row?.choice;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_surfaceStorageError(error), stackTrace);
    }
  }

  Future<void> saveAppearanceChoice(String choice) async {
    try {
      final String subjectId = _requireActive();
      final ProfileDatabase database = _requireDatabase();
      if (choice != 'system' && choice != 'light' && choice != 'dark') {
        throw const StorageSchemaException(
          'appearance choice is not supported',
        );
      }
      await database
          .into(database.appearanceRecords)
          .insertOnConflictUpdate(
            AppearanceRecordsCompanion.insert(
              subjectId: subjectId,
              choice: choice,
              updatedAtMs: _now(),
            ),
          );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_surfaceStorageError(error), stackTrace);
    }
  }

  Future<String> saveProblemReport({
    required String category,
    required String note,
    String? sessionId,
    String? exerciseId,
  }) async {
    try {
      final String subjectId = _requireActive();
      final ProfileDatabase database = _requireDatabase();
      final int createdAtMs = _now();
      const Set<String> categories = <String>{
        'app_issue',
        'exercise_instruction',
        'program_feels_wrong',
        'safety_concern',
        'content_issue',
      };
      if (!categories.contains(category)) {
        throw const StorageSchemaException('report category is not supported');
      }
      if (note.length > 500) {
        throw const StorageSchemaException('note is too long');
      }
      if (sessionId != null &&
          !await _workoutRecordExists(subjectId, sessionId)) {
        throw const StorageSchemaException('session is not stored');
      }
      final String? document = await loadProgramRecord();
      int? programRecordVersion;
      String? programRuleId;
      int? programRuleVersion;
      String? safetyRuleId;
      int? safetyRuleVersion;
      String? storedExerciseId;
      int? exerciseVersion;
      final LocalProgram? program = _decodeStoredProgram(document);
      if (exerciseId != null) {
        if (program == null) {
          throw const StorageSchemaException(
            'stored program could not be read',
          );
        }
        ProgramExercise? match;
        for (final ProgramExercise exercise in program.exercises) {
          if (exercise.exerciseId == exerciseId) {
            match = exercise;
            break;
          }
        }
        if (match == null) {
          throw const StorageSchemaException(
            'exercise is not in the stored program',
          );
        }
        programRecordVersion = program.recordVersion;
        programRuleId = program.ruleId;
        programRuleVersion = program.ruleVersion;
        safetyRuleId = program.safetyRuleId;
        safetyRuleVersion = program.safetyRuleVersion;
        storedExerciseId = match.exerciseId;
        exerciseVersion = match.exerciseVersion;
      } else if (program != null) {
        programRecordVersion = program.recordVersion;
        programRuleId = program.ruleId;
        programRuleVersion = program.ruleVersion;
        safetyRuleId = program.safetyRuleId;
        safetyRuleVersion = program.safetyRuleVersion;
      }
      final String reportId = _newEventId();
      await database
          .into(database.problemReportRecords)
          .insert(
            ProblemReportRecordsCompanion(
              reportId: Value<String>(reportId),
              subjectId: Value<String>(subjectId),
              category: Value<String>(category),
              note: Value<String>(note),
              programRecordVersion: Value<int?>(programRecordVersion),
              programRuleId: Value<String?>(programRuleId),
              programRuleVersion: Value<int?>(programRuleVersion),
              safetyRuleId: Value<String?>(safetyRuleId),
              safetyRuleVersion: Value<int?>(safetyRuleVersion),
              exerciseId: Value<String?>(storedExerciseId),
              exerciseVersion: Value<int?>(exerciseVersion),
              sessionId: Value<String?>(sessionId),
              createdAtMs: Value<int>(createdAtMs),
            ),
          );
      return reportId;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_surfaceStorageError(error), stackTrace);
    }
  }

  Future<StoredProblemReport?> loadProblemReport(String reportId) async {
    try {
      final String subjectId = _requireActive();
      final ProfileDatabase database = _requireDatabase();
      final ProblemReportRecord? row =
          await (database.select(database.problemReportRecords)..where(
                (ProblemReportRecords table) =>
                    table.subjectId.equals(subjectId) &
                    table.reportId.equals(reportId),
              ))
              .getSingleOrNull();
      if (row == null) {
        return null;
      }
      return StoredProblemReport(
        reportId: row.reportId,
        category: row.category,
        note: row.note,
        programRecordVersion: row.programRecordVersion,
        programRuleId: row.programRuleId,
        programRuleVersion: row.programRuleVersion,
        safetyRuleId: row.safetyRuleId,
        safetyRuleVersion: row.safetyRuleVersion,
        exerciseId: row.exerciseId,
        exerciseVersion: row.exerciseVersion,
        sessionId: row.sessionId,
        createdAtMs: row.createdAtMs,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_surfaceStorageError(error), stackTrace);
    }
  }

  Future<bool> hasWorkoutRecord(String sessionId) async {
    try {
      final String subjectId = _requireActive();
      final ProfileDatabase database = _requireDatabase();
      final WorkoutRecord? row =
          await (database.select(database.workoutRecords)..where(
                (WorkoutRecords table) =>
                    table.subjectId.equals(subjectId) &
                    table.sessionId.equals(sessionId),
              ))
              .getSingleOrNull();
      return row != null;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_surfaceStorageError(error), stackTrace);
    }
  }

  Future<String?> loadReadinessRecord(String sessionId) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final ReadinessRecord? row =
        await (database.select(database.readinessRecords)..where(
              (ReadinessRecords table) =>
                  table.subjectId.equals(subjectId) &
                  table.sessionId.equals(sessionId),
            ))
            .getSingleOrNull();
    return row?.documentJson;
  }

  Future<String?> loadAdaptationRecord(String sessionId) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final AdaptationRecord? row =
        await (database.select(database.adaptationRecords)..where(
              (AdaptationRecords table) =>
                  table.subjectId.equals(subjectId) &
                  table.sessionId.equals(sessionId),
            ))
            .getSingleOrNull();
    return row?.documentJson;
  }

  /// Insert readiness, then adaptation. A duplicate key rolls the pair back.
  Future<void> saveAdaptationPair({
    required String sessionId,
    required String readinessJson,
    required String adaptationJson,
    required int updatedAtMs,
  }) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await database.transaction(() async {
      await database
          .into(database.readinessRecords)
          .insert(
            ReadinessRecordsCompanion.insert(
              subjectId: subjectId,
              sessionId: sessionId,
              documentJson: readinessJson,
              updatedAtMs: updatedAtMs,
            ),
          );
      await database
          .into(database.adaptationRecords)
          .insert(
            AdaptationRecordsCompanion.insert(
              subjectId: subjectId,
              sessionId: sessionId,
              documentJson: adaptationJson,
              updatedAtMs: updatedAtMs,
            ),
          );
    });
  }

  Future<String?> loadFlareFollowup(String sessionId) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final FlareFollowupRecord? row =
        await (database.select(database.flareFollowupRecords)..where(
              (FlareFollowupRecords table) =>
                  table.subjectId.equals(subjectId) &
                  table.sessionId.equals(sessionId),
            ))
            .getSingleOrNull();
    return row?.documentJson;
  }

  /// Insert one envelope. A duplicate key throws and the first row stays.
  Future<void> saveFlareFollowup({
    required String sessionId,
    required String documentJson,
    required int updatedAtMs,
  }) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await database
        .into(database.flareFollowupRecords)
        .insert(
          FlareFollowupRecordsCompanion.insert(
            subjectId: subjectId,
            sessionId: sessionId,
            documentJson: documentJson,
            updatedAtMs: updatedAtMs,
          ),
        );
  }

  Future<void> deleteFlareFollowup(String sessionId) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await (database.delete(database.flareFollowupRecords)..where(
          (FlareFollowupRecords table) =>
              table.subjectId.equals(subjectId) &
              table.sessionId.equals(sessionId),
        ))
        .go();
  }

  Future<void> deleteAdaptationPair(String sessionId) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    await database.transaction(() async {
      await (database.delete(database.readinessRecords)..where(
            (ReadinessRecords table) =>
                table.subjectId.equals(subjectId) &
                table.sessionId.equals(sessionId),
          ))
          .go();
      await (database.delete(database.adaptationRecords)..where(
            (AdaptationRecords table) =>
                table.subjectId.equals(subjectId) &
                table.sessionId.equals(sessionId),
          ))
          .go();
    });
  }

  int clockMillis() => _now();

  Future<int?> workoutRecordUpdatedAtMs(String sessionId) async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    final WorkoutRecord? row =
        await (database.select(database.workoutRecords)..where(
              (WorkoutRecords table) =>
                  table.subjectId.equals(subjectId) &
                  table.sessionId.equals(sessionId),
            ))
            .getSingleOrNull();
    return row?.updatedAtMs;
  }

  /// Insert then throw. The transaction rolls back, so the draft stays.
  Future<void> interruptWorkoutSave({
    required String sessionId,
    required String documentJson,
  }) {
    return _queuedWorkout(() async {
      final ProfileDatabase database = _requireDatabase();
      final String subjectId = _requireActive();
      try {
        await database.transaction(() async {
          await database
              .into(database.workoutRecords)
              .insert(
                WorkoutRecordsCompanion.insert(
                  subjectId: subjectId,
                  sessionId: sessionId,
                  documentJson: documentJson,
                  updatedAtMs: _now(),
                ),
              );
          throw const StorageIoException('interrupted write');
        });
      } on StorageIoException {
        return;
      }
    });
  }

  Future<void> writeUserVersion(int version) async {
    if (version < 0 || version > 99) {
      throw const StorageIoException('rejected user version');
    }
    await _requireDatabase().customStatement('PRAGMA user_version = $version');
  }

  Future<void> reopenActive() async {
    final String? active = await keys.read(activeProfileItem);
    if (active == null || active.isEmpty) {
      throw const StorageKeyLoss();
    }
    final String subjectId = acceptSubject(raw: active);
    final String? keyHex = await keys.read(profileKeyItem(subjectId));
    if (keyHex == null) {
      throw const StorageKeyLoss();
    }
    await _closeCurrent();
    await _openExisting(subjectId, keyHex);
  }

  Future<void> interruptProbeWrite() async {
    final ProfileDatabase database = _requireDatabase();
    final String subjectId = _requireActive();
    try {
      await database.transaction(() async {
        await _insertProbe(database, subjectId, _now());
        throw const StorageIoException('interrupted write');
      });
    } on StorageIoException {
      return;
    }
  }

  Future<List<String>> eventPayloads() async {
    final List<LocalEvent> rows = await _requireDatabase()
        .select(_requireDatabase().localEvents)
        .get();
    return <String>[for (final LocalEvent row in rows) row.payloadText];
  }

  Future<List<String>> eventSubjectIds() async {
    final List<LocalEvent> rows = await _requireDatabase()
        .select(_requireDatabase().localEvents)
        .get();
    return <String>[for (final LocalEvent row in rows) row.subjectId];
  }

  Future<int?> createdAtMs() async {
    final String subjectId = _requireActive();
    final LocalProfile? row =
        await (_requireDatabase().select(_requireDatabase().localProfiles)
              ..where(
                (LocalProfiles table) => table.subjectId.equals(subjectId),
              ))
            .getSingleOrNull();
    return row?.createdAtMs;
  }

  File? get openDatabaseFile {
    final String? subjectId = _activeSubjectId;
    if (subjectId == null) {
      return null;
    }
    return _databaseFile(subjectId);
  }

  String? _activeSubjectId;

  Future<void> _openExisting(String subjectId, String keyHex) async {
    final File file = _databaseFile(subjectId);
    file.parent.createSync(recursive: true);
    await _excludeProfile(file.parent.path);
    onOpenStarted?.call();
    final ProfileDatabase database = ProfileDatabase.open(
      file: file,
      keyHex: keyHex,
    );
    _unpublishedOpens += 1;
    try {
      final List<LocalProfile> profiles = await database
          .select(database.localProfiles)
          .get();
      final int now = _now();
      if (profiles.isEmpty) {
        await database
            .into(database.localProfiles)
            .insert(
              LocalProfilesCompanion.insert(
                subjectId: subjectId,
                createdAtMs: now,
                lastActiveAtMs: now,
              ),
            );
        await _insertProbe(database, subjectId, now);
      } else {
        await (database.update(database.localProfiles)..where(
              (LocalProfiles table) => table.subjectId.equals(subjectId),
            ))
            .write(LocalProfilesCompanion(lastActiveAtMs: Value<int>(now)));
      }
      await _excludeProfile(file.parent.path);
      _database = database;
      _activeSubjectId = subjectId;
    } catch (error, stackTrace) {
      await database.close();
      onDatabaseClosed?.call();
      Error.throwWithStackTrace(_surfaceStorageError(error), stackTrace);
    } finally {
      _unpublishedOpens -= 1;
    }
  }

  Future<void> _excludeProfile(String path) async {
    try {
      await excludeFromBackup(path);
    } on StorageCipherUnavailable {
      rethrow;
    } on StorageSchemaException {
      rethrow;
    } on StorageKeyLoss {
      rethrow;
    } on StorageIoException {
      rethrow;
    } on SqliteException {
      rethrow;
    } on FileSystemException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const StorageIoException('backup exclusion failed'),
        stackTrace,
      );
    }
  }

  Future<void> _insertProbe(
    ProfileDatabase database,
    String subjectId,
    int createdAtMs,
  ) {
    return database
        .into(database.localEvents)
        .insert(
          LocalEventsCompanion.insert(
            eventId: _newEventId(),
            subjectId: subjectId,
            eventType: storageProbeType,
            payloadText: storageProbePayload,
            createdAtMs: createdAtMs,
          ),
        );
  }

  Future<void> _closeCurrent() async {
    final ProfileDatabase? database = _database;
    _database = null;
    _activeSubjectId = null;
    if (database == null) {
      return;
    }
    Object? failure;
    StackTrace? failureStack;
    try {
      final Future<void> Function()? beforeCheckpoint = onBeforeCheckpoint;
      if (beforeCheckpoint != null) {
        await beforeCheckpoint();
      }
      await database.checkpoint();
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    } finally {
      await database.close();
      onDatabaseClosed?.call();
    }
    if (failure != null && failureStack != null) {
      Error.throwWithStackTrace(failure, failureStack);
    }
  }

  ProfileDatabase _requireDatabase() {
    final ProfileDatabase? database = _database;
    if (database == null) {
      throw const StorageIoException('no open database');
    }
    return database;
  }

  String _requireActive() {
    final String? subjectId = _activeSubjectId;
    if (subjectId == null) {
      throw const StorageIoException('no active profile');
    }
    return subjectId;
  }

  int _now() => clock().toUtc().millisecondsSinceEpoch;

  /// A missing or unreadable program still saves when no exercise id was passed.
  LocalProgram? _decodeStoredProgram(String? document) {
    if (document == null) {
      return null;
    }
    try {
      return LocalProgram.decode(document);
    } on LocalProgramException {
      return null;
    }
  }

  String _newSubjectId() {
    final String subjectId = 'p-${_hex(16)}';
    final String accepted = acceptSubject(raw: subjectId);
    if (accepted != subjectId) {
      throw const StorageIoException('rejected generated subject');
    }
    return subjectId;
  }

  String _newKeyHex() {
    final String keyHex = _hex(32);
    if (!profileKeyHex.hasMatch(keyHex)) {
      throw const StorageIoException('rejected generated key');
    }
    return keyHex;
  }

  String _newEventId() {
    final List<int> bytes = <int>[
      for (int index = 0; index < 16; index++) random.nextInt(256),
    ];
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final String hex = bytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _hex(int byteCount) {
    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < byteCount; index++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Directory _profileDirectory(String subjectId) {
    return Directory(
      '${supportDirectory.path}${Platform.pathSeparator}profiles'
      '${Platform.pathSeparator}$subjectId',
    );
  }

  File _copyAcceptedFile(String subjectId) {
    return File(
      '${_profileDirectory(subjectId).path}${Platform.pathSeparator}$copyAcceptedName',
    );
  }

  String _sha256Text(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }

  Future<bool> _shouldEnqueueOutbox(
    ProfileDatabase database,
    String subjectId,
  ) async {
    if (isCopyAccepted(subjectId)) {
      return true;
    }
    final SyncOutboxData? row =
        await (database.select(database.syncOutbox)
              ..where((SyncOutbox table) => table.subjectId.equals(subjectId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<SyncOutboxData?> _outboxRow(
    ProfileDatabase database,
    String subjectId,
    String entity,
    String localKey,
  ) {
    return (database.select(database.syncOutbox)..where(
          (SyncOutbox table) =>
              table.subjectId.equals(subjectId) &
              table.entity.equals(entity) &
              table.localKey.equals(localKey),
        ))
        .getSingleOrNull();
  }

  Future<bool> _upsertProgramOutbox(
    ProfileDatabase database,
    String subjectId,
    String documentJson,
  ) async {
    final SyncOutboxData? existing = await _outboxRow(
      database,
      subjectId,
      _programOutboxEntity,
      subjectId,
    );
    if (existing == null) {
      await _insertPendingOutbox(
        database,
        subjectId: subjectId,
        entity: _programOutboxEntity,
        localKey: subjectId,
        documentJson: documentJson,
      );
      return true;
    }
    if (existing.state != _outboxPending) {
      return false;
    }
    await (database.update(database.syncOutbox)..where(
          (SyncOutbox table) =>
              table.subjectId.equals(subjectId) &
              table.eventId.equals(existing.eventId),
        ))
        .write(
          SyncOutboxCompanion(
            documentSha256: Value<String>(_sha256Text(documentJson)),
            updatedAtMs: Value<int>(_now()),
          ),
        );
    return true;
  }

  Future<bool> _insertMissingWorkoutOutbox(
    ProfileDatabase database,
    String subjectId,
    String sessionId,
    String documentJson,
  ) async {
    final SyncOutboxData? existing = await _outboxRow(
      database,
      subjectId,
      _workoutOutboxEntity,
      sessionId,
    );
    if (existing != null) {
      return false;
    }
    final WorkoutRecord? stored =
        await (database.select(database.workoutRecords)..where(
              (WorkoutRecords table) =>
                  table.subjectId.equals(subjectId) &
                  table.sessionId.equals(sessionId),
            ))
            .getSingleOrNull();
    if (stored == null) {
      return false;
    }
    await _insertPendingOutbox(
      database,
      subjectId: subjectId,
      entity: _workoutOutboxEntity,
      localKey: sessionId,
      documentJson: stored.documentJson,
    );
    return true;
  }

  Future<void> _insertPendingOutbox(
    ProfileDatabase database, {
    required String subjectId,
    required String entity,
    required String localKey,
    required String documentJson,
  }) {
    return database
        .into(database.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            subjectId: subjectId,
            eventId: _newEventId(),
            entity: entity,
            localKey: localKey,
            documentSha256: _sha256Text(documentJson),
            state: _outboxPending,
            updatedAtMs: _now(),
          ),
        );
  }

  Future<String?> _outboxDocumentJson(
    ProfileDatabase database,
    String subjectId,
    String entity,
    String localKey,
  ) async {
    if (entity == _programOutboxEntity) {
      final ProgramRecord? row =
          await (database.select(database.programRecords)..where(
                (ProgramRecords table) => table.subjectId.equals(subjectId),
              ))
              .getSingleOrNull();
      return row?.documentJson;
    }
    if (entity == _workoutOutboxEntity) {
      final WorkoutRecord? row =
          await (database.select(database.workoutRecords)..where(
                (WorkoutRecords table) =>
                    table.subjectId.equals(subjectId) &
                    table.sessionId.equals(localKey),
              ))
              .getSingleOrNull();
      return row?.documentJson;
    }
    return null;
  }

  Object _surfaceStorageError(Object error) {
    if (error is StorageSchemaException ||
        error is StorageCipherUnavailable ||
        error is StorageKeyLoss ||
        error is StorageIoException ||
        error is SqliteException ||
        error is FileSystemException) {
      return error;
    }
    // Drift's background connection sends the cause as text, not the original type.
    final String text = error.toString();
    const String schemaPrefix = 'StorageSchemaException: ';
    if (text.startsWith(schemaPrefix)) {
      return StorageSchemaException(text.substring(schemaPrefix.length));
    }
    if (text.startsWith('StorageCipherUnavailable')) {
      return const StorageCipherUnavailable();
    }
    if (text.startsWith('StorageKeyLoss')) {
      return const StorageKeyLoss();
    }
    if (error.runtimeType.toString() == 'DriftRemoteException') {
      // That text can include the SQL that carried the key.
      return const StorageIoException('local database request failed');
    }
    return error;
  }

  File _databaseFile(String subjectId) {
    return File(
      '${_profileDirectory(subjectId).path}${Platform.pathSeparator}helpmemove.db',
    );
  }
}
