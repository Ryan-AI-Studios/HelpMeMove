import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
const String _profileKeyPrefix = 'profile-key.';

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

  ProfileDatabase? _database;
  Completer<void>? _workoutTurn;

  /// Tests override this to occupy the workout write queue.
  Future<void> onWorkoutQueueEntered() async {}

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

  Future<String> openActive() async {
    try {
      final String? active = await keys.read(activeProfileItem);
      if (active == null || active.isEmpty) {
        await createProfile();
        return '/';
      }
      acceptSubject(raw: active);
      final String? keyHex = await keys.read(profileKeyItem(active));
      if (keyHex == null) {
        await _closeCurrent();
        return '/key-loss';
      }
      await _closeCurrent();
      await _openExisting(active, keyHex);
      return '/';
    } on StorageKeyLoss {
      return '/key-loss';
    } on StorageCipherUnavailable {
      return '/storage-failure';
    } on StorageSchemaException {
      return '/storage-failure';
    } on StorageIoException {
      return '/storage-failure';
    } on SqliteException {
      return '/storage-failure';
    } on FileSystemException {
      return '/storage-failure';
    }
  }

  Future<String> createProfile() async {
    await _closeCurrent();
    final String subjectId = _newSubjectId();
    final String keyHex = _newKeyHex();
    await keys.write(profileKeyItem(subjectId), keyHex);
    await _openExisting(subjectId, keyHex);
    await keys.write(activeProfileItem, subjectId);
    return subjectId;
  }

  Future<void> switchTo(String raw) async {
    final String subjectId = acceptSubject(raw: raw);
    final String? keyHex = await keys.read(profileKeyItem(subjectId));
    if (keyHex == null) {
      throw const StorageKeyLoss();
    }
    await _closeCurrent();
    await _openExisting(subjectId, keyHex);
    await keys.write(activeProfileItem, subjectId);
  }

  Future<String> resetActive() async {
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

  Future<void> close() => _closeCurrent();

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
    await database
        .into(database.programRecords)
        .insertOnConflictUpdate(
          ProgramRecordsCompanion.insert(
            subjectId: subjectId,
            documentJson: documentJson,
            updatedAtMs: _now(),
          ),
        );
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
      });
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
    final ProfileDatabase database = ProfileDatabase.open(
      file: file,
      keyHex: keyHex,
    );
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
      _database = database;
      _activeSubjectId = subjectId;
    } catch (error, stackTrace) {
      await database.close();
      Error.throwWithStackTrace(_surfaceStorageError(error), stackTrace);
    }
    await excludeFromBackup(file.parent.path);
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
    await database.checkpoint();
    await database.close();
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
