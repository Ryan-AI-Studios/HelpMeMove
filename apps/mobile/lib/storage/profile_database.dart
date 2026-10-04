import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:helpmemove/storage/encryption.dart';
import 'package:helpmemove/storage/storage_exception.dart';

part 'profile_database.g.dart';

class LocalProfiles extends Table {
  @override
  String get tableName => 'local_profiles';

  TextColumn get subjectId => text()();

  IntColumn get createdAtMs => integer()();

  IntColumn get lastActiveAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{subjectId};
}

class IntakeDrafts extends Table {
  @override
  String get tableName => 'intake_drafts';

  TextColumn get subjectId => text()();

  TextColumn get documentJson => text()();

  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{subjectId};
}

class AssessmentDrafts extends Table {
  @override
  String get tableName => 'assessment_drafts';

  TextColumn get subjectId => text()();

  TextColumn get documentJson => text()();

  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{subjectId};
}

class AssessmentRecords extends Table {
  @override
  String get tableName => 'assessment_records';

  TextColumn get subjectId => text()();

  TextColumn get documentJson => text()();

  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{subjectId};
}

class ProgramRecords extends Table {
  @override
  String get tableName => 'program_records';

  TextColumn get subjectId => text()();

  TextColumn get documentJson => text()();

  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{subjectId};
}

class WorkoutDrafts extends Table {
  @override
  String get tableName => 'workout_drafts';

  TextColumn get subjectId => text()();

  TextColumn get documentJson => text()();

  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{subjectId};
}

class WorkoutRecords extends Table {
  @override
  String get tableName => 'workout_records';

  TextColumn get subjectId => text()();

  TextColumn get sessionId => text()();

  TextColumn get documentJson => text()();

  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{subjectId, sessionId};
}

class LocalEvents extends Table {
  @override
  String get tableName => 'local_events';

  TextColumn get eventId => text()();

  TextColumn get subjectId => text()();

  TextColumn get eventType => text()();

  TextColumn get payloadText => text()();

  IntColumn get createdAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{eventId};

  @override
  List<String> get customConstraints => const <String>[
    "CHECK (event_type = 'storage-probe')",
    "CHECK (payload_text = 'helpmemove-storage-probe')",
  ];
}

const String storageProbeType = 'storage-probe';
const String storageProbePayload = 'helpmemove-storage-probe';

void rejectSchemaUpgrade(int from, int to) {
  throw StorageSchemaException(
    'schema upgrade from $from to $to is not supported',
  );
}

QueryExecutor openEncryptedExecutor({
  required File file,
  required String keyHex,
}) {
  // Each profile is its own file. Opening the next one is not a shared executor.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return NativeDatabase.createInBackground(
    file,
    setup: (Database database) {
      applyEncryptionSetup(database, keyHex);
    },
  );
}

@DriftDatabase(
  tables: [
    LocalProfiles,
    LocalEvents,
    IntakeDrafts,
    AssessmentDrafts,
    AssessmentRecords,
    ProgramRecords,
    WorkoutDrafts,
    WorkoutRecords,
  ],
)
class ProfileDatabase extends _$ProfileDatabase {
  ProfileDatabase(super.executor);

  ProfileDatabase.open({required File file, required String keyHex})
    : super(openEncryptedExecutor(file: file, keyHex: keyHex));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from == 1 && to == 2) {
        await migrator.createTable(intakeDrafts);
        return;
      }
      if (from == 2 && to == 3) {
        await migrator.createTable(assessmentDrafts);
        await migrator.createTable(assessmentRecords);
        return;
      }
      if (from == 3 && to == 4) {
        await migrator.createTable(programRecords);
        return;
      }
      if (from == 4 && to == 5) {
        await migrator.createTable(workoutDrafts);
        await migrator.createTable(workoutRecords);
        return;
      }
      rejectSchemaUpgrade(from, to);
    },
  );

  Future<void> checkpoint() {
    return customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
  }
}
