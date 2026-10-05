import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart' as drift_native;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/encryption.dart';
import 'package:helpmemove/storage/profile_database.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-storage');
  });

  tearDown(() async {
    await live?.close();
    live = null;
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  ProfileStore openStore({DateTime Function()? clock, List<String>? excluded}) {
    final ProfileStore store = ProfileStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: clock ?? () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(7),
      excludeFromBackup: (String path) async {
        excluded?.add(path);
      },
    );
    live = store;
    return store;
  }

  test('production secure storage uses the pinned options', () {
    final FlutterSecureStorage storage = productionSecureStorage();
    expect(storage.aOptions.toMap()['resetOnError'], 'false');
    expect(storage.aOptions.toMap()['enforceBiometrics'], 'false');
    expect(storage.aOptions.storageNamespace, 'helpmemove');
    expect(
      storage.iOptions.accessibility,
      KeychainAccessibility.first_unlock_this_device,
    );
    expect(storage.iOptions.synchronizable, isFalse);
    expect(storage.iOptions.groupId, isNull);
  });

  test('android backup rules exclude the profiles directory', () {
    final String manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    final String fullBackup = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final String extraction = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    expect(fullBackup, contains('domain="file"'));
    expect(fullBackup, contains('path="profiles"'));
    expect(extraction, contains('<cloud-backup>'));
    expect(extraction, contains('<device-transfer>'));
    expect(extraction, contains('path="profiles"'));
  });

  test('first profile is encrypted and uses a bridge subject id', () async {
    final List<String> excluded = <String>[];
    final ProfileStore store = openStore(excluded: excluded);
    final String subjectId = await store.createProfile();
    expect(RegExp(r'^p-[0-9a-f]{32}$').hasMatch(subjectId), isTrue);
    expect(acceptSubject(raw: subjectId), subjectId);
    expect(await store.eventPayloads(), <String>[storageProbePayload]);
    expect(await store.eventSubjectIds(), <String>[subjectId]);
    expect(
      await store.createdAtMs(),
      DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch,
    );
    expect(excluded, isNotEmpty);

    await store.checkpoint();
    final File databaseFile = store.openDatabaseFile!;
    expect(_startsWithSqliteHeader(databaseFile), isFalse);
    _expectNoProbeMarker(databaseFile.parent);
  });

  test('two profiles keep separate files and keys', () async {
    final ProfileStore store = openStore();
    final String first = await store.createProfile();
    final String firstKey = (await store.keys.read(profileKeyItem(first)))!;
    final File firstFile = store.openDatabaseFile!;
    final String second = await store.createProfile();
    final String secondKey = (await store.keys.read(profileKeyItem(second)))!;
    expect(second, isNot(first));
    expect(secondKey, isNot(firstKey));
    expect(store.openDatabaseFile!.path, isNot(firstFile.path));
    expect(await store.eventSubjectIds(), <String>[second]);

    await store.switchTo(first);
    expect(await store.eventSubjectIds(), <String>[first]);
    expect(await store.eventPayloads(), <String>[storageProbePayload]);
  });

  test('a thrown transaction leaves no partial event', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    expect(await store.eventPayloads(), hasLength(1));
    await store.interruptProbeWrite();
    expect(await store.eventPayloads(), hasLength(1));
  });

  test('user version 99 fails closed and keeps the probe', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final File databaseFile = store.openDatabaseFile!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.writeUserVersion(99);
    await store.close();

    await expectLater(
      store.reopenActive(),
      throwsA(isA<StorageSchemaException>()),
    );

    final Database raw = sqlite3.open(databaseFile.path);
    applyEncryptionSetup(raw, keyHex);
    expect(raw.select('PRAGMA user_version').first.columnAt(0), 99);
    expect(
      raw.select('SELECT payload_text FROM local_events').first.columnAt(0),
      storageProbePayload,
    );
    raw.close();
  });

  test('a wrong key does not reveal or destroy the probe', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final String original = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();
    await store.keys.write(profileKeyItem(subjectId), 'ab' * 32);

    await expectLater(store.switchTo(subjectId), throwsA(anything));

    await store.keys.write(profileKeyItem(subjectId), original);
    await store.switchTo(subjectId);
    expect(await store.eventPayloads(), <String>[storageProbePayload]);
  });

  test(
    'missing key routes to key loss and reset creates a new profile',
    () async {
      final ProfileStore store = openStore();
      final String first = await store.createProfile();
      final File firstFile = store.openDatabaseFile!;
      await store.keys.delete(profileKeyItem(first));
      expect(await store.openActive(), '/key-loss');

      expect(await store.resetActive(), '/');
      expect(firstFile.existsSync(), isFalse);
      final String? second = await store.keys.read(activeProfileItem);
      expect(second, isNot(first));
      expect(RegExp(r'^p-[0-9a-f]{32}$').hasMatch(second!), isTrue);
      expect(await store.eventSubjectIds(), <String>[second]);
    },
  );

  test('schema upgrade is rejected', () {
    expect(
      () => rejectSchemaUpgrade(1, 3),
      throwsA(isA<StorageSchemaException>()),
    );
    expect(
      () => rejectSchemaUpgrade(2, 1),
      throwsA(isA<StorageSchemaException>()),
    );
    expect(
      () => rejectSchemaUpgrade(2, 4),
      throwsA(isA<StorageSchemaException>()),
    );
    expect(
      () => rejectSchemaUpgrade(1, 4),
      throwsA(isA<StorageSchemaException>()),
    );
    expect(
      () => rejectSchemaUpgrade(3, 5),
      throwsA(isA<StorageSchemaException>()),
    );
    expect(
      () => rejectSchemaUpgrade(4, 6),
      throwsA(isA<StorageSchemaException>()),
    );
    expect(
      () => rejectSchemaUpgrade(5, 4),
      throwsA(isA<StorageSchemaException>()),
    );
    expect(
      () => rejectSchemaUpgrade(5, 7),
      throwsA(isA<StorageSchemaException>()),
    );
    expect(
      () => rejectSchemaUpgrade(6, 7),
      throwsA(isA<StorageSchemaException>()),
    );
  });

  test('onUpgrade accepts 6 to 7 and rejects the other new pairs', () async {
    final ProfileDatabase database = ProfileDatabase(
      drift_native.NativeDatabase.memory(),
    );
    addTearDown(database.close);
    await database.customSelect('SELECT 1').get();
    final Future<void> Function(drift.Migrator, int, int) upgrade =
        database.migration.onUpgrade;
    final drift.Migrator migrator = database.createMigrator();
    await database.customStatement(
      'DROP TABLE IF EXISTS flare_followup_records',
    );
    await upgrade(migrator, 6, 7);
    final List<drift.QueryRow> created = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'flare_followup_records'",
        )
        .get();
    expect(created, hasLength(1));
    await expectLater(
      upgrade(migrator, 5, 7),
      throwsA(isA<StorageSchemaException>()),
    );
    await expectLater(
      upgrade(migrator, 6, 8),
      throwsA(isA<StorageSchemaException>()),
    );
    await database.customStatement('DROP TABLE IF EXISTS appearance_records');
    await database.customStatement(
      'DROP TABLE IF EXISTS problem_report_records',
    );
    await upgrade(migrator, 7, 8);
    final List<drift.QueryRow> appearance = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'appearance_records'",
        )
        .get();
    expect(appearance, hasLength(1));
    final List<drift.QueryRow> reportsAfter78 = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'problem_report_records'",
        )
        .get();
    expect(reportsAfter78, isEmpty);
    await expectLater(
      upgrade(migrator, 7, 9),
      throwsA(isA<StorageSchemaException>()),
    );
    final List<drift.QueryRow> reportsAfter79 = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'problem_report_records'",
        )
        .get();
    expect(reportsAfter79, isEmpty);
    await upgrade(migrator, 8, 9);
    final List<drift.QueryRow> reports = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'problem_report_records'",
        )
        .get();
    expect(reports, hasLength(1));
    await expectLater(
      upgrade(migrator, 9, 10),
      throwsA(isA<StorageSchemaException>()),
    );
    await database.customStatement('DROP TABLE IF EXISTS readiness_records');
    await database.customStatement('DROP TABLE IF EXISTS adaptation_records');
    await upgrade(migrator, 5, 6);
    final List<drift.QueryRow> readiness = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'readiness_records'",
        )
        .get();
    expect(readiness, hasLength(1));
    expect(database.schemaVersion, 9);
  });

  test('schema 2 opened by schema 4 is rejected', () async {
    const String document =
        '{"draft_version":1,"intent":"fitness","notice_id":null,"schema_ack":null,"goals":[],"equipment":[],"areas":[],"note":"kept","severity":0,"step":"intent"}';
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final File file = store.openDatabaseFile!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();

    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    raw.execute('DROP TABLE IF EXISTS assessment_drafts');
    raw.execute('DROP TABLE IF EXISTS assessment_records');
    raw.execute('DROP TABLE IF EXISTS program_records');
    raw.execute('DROP TABLE IF EXISTS workout_drafts');
    raw.execute('DROP TABLE IF EXISTS workout_records');
    raw.execute('DELETE FROM intake_drafts');
    raw.execute(
      'INSERT INTO intake_drafts (subject_id, document_json, updated_at_ms) VALUES (?, ?, ?)',
      <Object>[subjectId, document, 5],
    );
    raw.execute('PRAGMA user_version = 2');
    raw.close();

    await expectLater(
      store.reopenActive(),
      throwsA(isA<StorageSchemaException>()),
    );

    final Database unchanged = sqlite3.open(file.path);
    applyEncryptionSetup(unchanged, keyHex);
    expect(unchanged.select('PRAGMA user_version').first.columnAt(0), 2);
    expect(
      unchanged
          .select('SELECT document_json FROM intake_drafts')
          .first
          .columnAt(0),
      document,
    );
    expect(
      unchanged
          .select('SELECT payload_text FROM local_events')
          .first
          .columnAt(0),
      storageProbePayload,
    );
    final ResultSet tables = unchanged.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('assessment_drafts', 'assessment_records', 'program_records')",
    );
    expect(tables, isEmpty);
    unchanged.close();
  });

  test('schema 3 opened by schema 5 is rejected', () async {
    const String intake = '{"draft_version":1,"goals":["control"]}';
    const String assessment =
        '{"record_version":1,"instrument_id":"syn-assessment-core"}';
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final File file = store.openDatabaseFile!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();

    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    raw.execute('DROP TABLE IF EXISTS program_records');
    raw.execute('DROP TABLE IF EXISTS workout_drafts');
    raw.execute('DROP TABLE IF EXISTS workout_records');
    raw.execute('DELETE FROM intake_drafts');
    raw.execute(
      'INSERT INTO intake_drafts (subject_id, document_json, updated_at_ms) VALUES (?, ?, ?)',
      <Object>[subjectId, intake, 5],
    );
    raw.execute('DELETE FROM assessment_records');
    raw.execute(
      'INSERT INTO assessment_records (subject_id, document_json, updated_at_ms) VALUES (?, ?, ?)',
      <Object>[subjectId, assessment, 6],
    );
    raw.execute('PRAGMA user_version = 3');
    raw.close();

    await expectLater(
      store.reopenActive(),
      throwsA(isA<StorageSchemaException>()),
    );

    final Database unchanged = sqlite3.open(file.path);
    applyEncryptionSetup(unchanged, keyHex);
    expect(unchanged.select('PRAGMA user_version').first.columnAt(0), 3);
    expect(
      unchanged
          .select('SELECT document_json FROM intake_drafts')
          .first
          .columnAt(0),
      intake,
    );
    expect(
      unchanged
          .select('SELECT document_json FROM assessment_records')
          .first
          .columnAt(0),
      assessment,
    );
    final ResultSet tables = unchanged.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('program_records', 'workout_drafts', 'workout_records')",
    );
    expect(tables, isEmpty);
    unchanged.close();
  });

  test('schema 4 reopen fails closed and does not become version 6', () async {
    const String program =
        '{"record_version":1,"rule_id":"syn-program-core","exercises":[]}';
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    await store.saveProgramRecord(program);
    final File file = store.openDatabaseFile!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();

    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    raw.execute('DROP TABLE IF EXISTS workout_drafts');
    raw.execute('DROP TABLE IF EXISTS workout_records');
    raw.execute('DROP TABLE IF EXISTS readiness_records');
    raw.execute('DROP TABLE IF EXISTS adaptation_records');
    raw.execute('PRAGMA user_version = 4');
    raw.close();

    await expectLater(
      store.reopenActive(),
      throwsA(isA<StorageSchemaException>()),
    );

    final Database unchanged = sqlite3.open(file.path);
    applyEncryptionSetup(unchanged, keyHex);
    expect(unchanged.select('PRAGMA user_version').first.columnAt(0), 4);
    expect(
      unchanged
          .select('SELECT document_json FROM program_records')
          .first
          .columnAt(0),
      program,
    );
    unchanged.close();
  });

  test('schema 5 opened by schema 7 is rejected', () async {
    const String program =
        '{"record_version":1,"rule_id":"syn-program-core","exercises":[]}';
    const String sessionId = '11111111-1111-4111-8111-111111111111';
    const String workout =
        '{"session_id":"11111111-1111-4111-8111-111111111111"}';
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    await store.saveProgramRecord(program);
    await store.saveWorkoutTerminal(
      sessionId: sessionId,
      documentJson: workout,
    );
    final File file = store.openDatabaseFile!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();

    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    raw.execute('DROP TABLE IF EXISTS readiness_records');
    raw.execute('DROP TABLE IF EXISTS adaptation_records');
    raw.execute('DROP TABLE IF EXISTS flare_followup_records');
    raw.execute('PRAGMA user_version = 5');
    raw.close();

    await expectLater(
      store.reopenActive(),
      throwsA(isA<StorageSchemaException>()),
    );

    final Database unchanged = sqlite3.open(file.path);
    applyEncryptionSetup(unchanged, keyHex);
    expect(unchanged.select('PRAGMA user_version').first.columnAt(0), 5);
    expect(
      unchanged
          .select('SELECT document_json FROM program_records')
          .first
          .columnAt(0),
      program,
    );
    expect(
      unchanged
          .select('SELECT document_json FROM workout_records')
          .first
          .columnAt(0),
      workout,
    );
    unchanged.close();
  });

  test('schema 8 gains problem_report_records and keeps appearance flare and program rows', () async {
    const String program =
        '{"record_version":1,"rule_id":"syn-program-core","exercises":[]}';
    const String sessionId = '11111111-1111-4111-8111-111111111111';
    const String workout =
        '{"session_id":"11111111-1111-4111-8111-111111111111"}';
    const String readiness = '{"soreness":"low"}';
    const String adaptation = '{"action":"maintain"}';
    const String flare = '{"choice":"worse_today","action":"keep_program"}';
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    await store.saveProgramRecord(program);
    await store.saveWorkoutTerminal(
      sessionId: sessionId,
      documentJson: workout,
    );
    await store.saveAdaptationPair(
      sessionId: sessionId,
      readinessJson: readiness,
      adaptationJson: adaptation,
      updatedAtMs: 6,
    );
    await store.saveFlareFollowup(
      sessionId: sessionId,
      documentJson: flare,
      updatedAtMs: 6,
    );
    await store.saveAppearanceChoice('dark');
    final File file = store.openDatabaseFile!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();

    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    raw.execute('DROP TABLE IF EXISTS problem_report_records');
    raw.execute('PRAGMA user_version = 8');
    raw.close();

    await store.reopenActive();
    expect(await store.loadProgramRecord(), program);
    expect(await store.workoutRecordDocuments(), <String>[workout]);
    expect(await store.loadReadinessRecord(sessionId), readiness);
    expect(await store.loadAdaptationRecord(sessionId), adaptation);
    expect(await store.loadFlareFollowup(sessionId), flare);
    expect(await store.loadAppearanceChoice(), 'dark');
    await store.close();

    final Database upgraded = sqlite3.open(file.path);
    applyEncryptionSetup(upgraded, keyHex);
    expect(upgraded.select('PRAGMA user_version').first.columnAt(0), 9);
    expect(
      upgraded
          .select('SELECT COUNT(*) FROM problem_report_records')
          .first
          .columnAt(0),
      0,
    );
    expect(
      upgraded
          .select('SELECT choice FROM appearance_records')
          .first
          .columnAt(0),
      'dark',
    );
    expect(
      upgraded
          .select('SELECT document_json FROM flare_followup_records')
          .first
          .columnAt(0),
      flare,
    );
    expect(
      upgraded
          .select('SELECT document_json FROM program_records')
          .first
          .columnAt(0),
      program,
    );
    upgraded.close();
  });

  test('schema 7 does not jump to schema 9', () async {
    const String program =
        '{"record_version":1,"rule_id":"syn-program-core","exercises":[]}';
    const String sessionId = '11111111-1111-4111-8111-111111111111';
    const String workout =
        '{"session_id":"11111111-1111-4111-8111-111111111111"}';
    const String readiness = '{"soreness":"low"}';
    const String adaptation = '{"action":"maintain"}';
    const String flare = '{"choice":"worse_today","action":"keep_program"}';
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    await store.saveProgramRecord(program);
    await store.saveWorkoutTerminal(
      sessionId: sessionId,
      documentJson: workout,
    );
    await store.saveAdaptationPair(
      sessionId: sessionId,
      readinessJson: readiness,
      adaptationJson: adaptation,
      updatedAtMs: 6,
    );
    await store.saveFlareFollowup(
      sessionId: sessionId,
      documentJson: flare,
      updatedAtMs: 6,
    );
    await store.saveAppearanceChoice('dark');
    final File file = store.openDatabaseFile!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();

    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    raw.execute('PRAGMA user_version = 7');
    raw.close();

    await expectLater(
      store.reopenActive(),
      throwsA(isA<StorageSchemaException>()),
    );

    final Database unchanged = sqlite3.open(file.path);
    applyEncryptionSetup(unchanged, keyHex);
    expect(unchanged.select('PRAGMA user_version').first.columnAt(0), 7);
    expect(
      unchanged
          .select('SELECT document_json FROM program_records')
          .first
          .columnAt(0),
      program,
    );
    expect(
      unchanged
          .select('SELECT document_json FROM workout_records')
          .first
          .columnAt(0),
      workout,
    );
    expect(
      unchanged
          .select('SELECT document_json FROM readiness_records')
          .first
          .columnAt(0),
      readiness,
    );
    expect(
      unchanged
          .select('SELECT document_json FROM adaptation_records')
          .first
          .columnAt(0),
      adaptation,
    );
    expect(
      unchanged
          .select('SELECT document_json FROM flare_followup_records')
          .first
          .columnAt(0),
      flare,
    );
    expect(
      unchanged
          .select('SELECT choice FROM appearance_records')
          .first
          .columnAt(0),
      'dark',
    );
    unchanged.close();
  });

  test('schema 6 does not jump to schema 8', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final File file = store.openDatabaseFile!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();

    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    raw.execute('PRAGMA user_version = 6');
    raw.close();

    await expectLater(
      store.reopenActive(),
      throwsA(isA<StorageSchemaException>()),
    );

    final Database unchanged = sqlite3.open(file.path);
    applyEncryptionSetup(unchanged, keyHex);
    expect(unchanged.select('PRAGMA user_version').first.columnAt(0), 6);
    unchanged.close();
  });

  test('assessment record round-trips and uses the store clock', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    const String record =
        '{"record_version":1,"instrument_id":"syn-assessment-core"}';
    const String draft = '{"record_version":1}';
    await store.saveAssessmentRecord(record);
    await store.saveAssessmentDraft(draft);
    expect(await store.loadAssessmentRecord(), record);
    expect(await store.loadAssessmentDraft(), draft);
    final File file = store.openDatabaseFile!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();

    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    final ResultSet rows = raw.select(
      'SELECT document_json, updated_at_ms FROM assessment_records',
    );
    expect(rows, hasLength(1));
    expect(rows.first.columnAt(0), record);
    expect(
      rows.first.columnAt(1),
      DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch,
    );
    raw.close();

    await store.reopenActive();
    await store.deleteAssessmentDraft();
    expect(await store.loadAssessmentDraft(), isNull);
    expect(await store.loadAssessmentRecord(), record);
    await store.deleteAssessmentRecord();
    expect(await store.loadAssessmentRecord(), isNull);
  });

  test('program record round-trips and leaves no rule id after checkpoint', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    const String record =
        '{"record_version":1,"rule_id":"syn-program-core","rule_version":1,"safety_rule_id":"syn-safety-core","safety_rule_version":1,"session_minutes":15,"exercises":[]}';
    await store.saveProgramRecord(record);
    expect(await store.loadProgramRecord(), record);
    final File file = store.openDatabaseFile!;
    final String subjectId = (await store.keys.read(activeProfileItem))!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();

    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    final ResultSet rows = raw.select(
      'SELECT document_json, updated_at_ms FROM program_records',
    );
    expect(rows, hasLength(1));
    expect(rows.first.columnAt(0), record);
    expect(
      rows.first.columnAt(1),
      DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch,
    );
    raw.close();

    await store.reopenActive();
    expect(await store.loadProgramRecord(), record);
    await store.checkpoint();
    _expectMarkerAbsent(store.openDatabaseFile!.parent, 'syn-program-core');
    await store.deleteProgramRecord();
    expect(await store.loadProgramRecord(), isNull);
  });

  test(
    'checkpoint removes the instrument id bytes from the profile directory',
    () async {
      final ProfileStore store = openStore();
      await store.createProfile();
      await store.saveAssessmentRecord(
        '{"instrument_id":"syn-assessment-core","record_version":1}',
      );
      await store.checkpoint();
      _expectMarkerAbsent(
        store.openDatabaseFile!.parent,
        'syn-assessment-core',
      );
    },
  );

  test(
    'workout draft and record use the store clock and one session row',
    () async {
      final ProfileStore store = openStore();
      await store.createProfile();
      const String document =
          '{"exercise_id":"syn-shoulder-isometric","state":"preparing"}';
      final String sessionId = store.newSessionId();
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(sessionId),
        isTrue,
      );
      expect(store.newSessionId(), isNot(sessionId));
      final List<String> events = await store.eventPayloads();
      await store.saveWorkoutDraft(document);
      expect(await store.loadWorkoutDraft(), document);
      await store.deleteWorkoutDraft();
      expect(await store.loadWorkoutDraft(), isNull);
      expect(await store.eventPayloads(), events);

      await store.saveWorkoutDraft(document);
      await store.saveWorkoutTerminal(
        sessionId: sessionId,
        documentJson: document,
      );
      expect(await store.loadWorkoutDraft(), isNull);
      expect(await store.workoutRecordCount(), 1);
      expect(
        await store.workoutRecordUpdatedAtMs(sessionId),
        DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch,
      );
      await store.saveWorkoutDraft(document);
      await store.saveWorkoutTerminal(
        sessionId: sessionId,
        documentJson: document,
      );
      expect(await store.workoutRecordCount(), 1);
      expect(await store.loadWorkoutDraft(), isNull);
      expect(await store.eventPayloads(), events);

      await store.saveWorkoutDraft(document);
      await store.interruptWorkoutSave(
        sessionId: store.newSessionId(),
        documentJson: document,
      );
      expect(await store.loadWorkoutDraft(), document);
      expect(await store.workoutRecordCount(), 1);
      await store.close();
      await store.reopenActive();
      expect(await store.loadWorkoutDraft(), document);
      expect(await store.loadProgramRecord(), isNull);
    },
  );

  test('a recorded session is not written back as the draft', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    const String sessionId = '11111111-1111-4111-8111-111111111111';
    const String recorded =
        '{"session_id":"11111111-1111-4111-8111-111111111111","state":"completed"}';
    const String fresh =
        '{"session_id":"22222222-2222-4222-8222-222222222222","state":"preparing"}';
    await store.saveWorkoutDraft(recorded);
    await store.saveWorkoutTerminal(
      sessionId: sessionId,
      documentJson: recorded,
    );
    await store.saveWorkoutDraft(recorded);
    expect(await store.loadWorkoutDraft(), isNull);
    expect(await store.workoutRecordCount(), 1);
    await store.saveWorkoutDraft(fresh);
    expect(await store.loadWorkoutDraft(), fresh);
  });

  test(
    'checkpoint removes the session markers from the profile directory',
    () async {
      final ProfileStore store = openStore();
      await store.createProfile();
      const String document =
          '{"exercise_id":"syn-shoulder-isometric","note":"This hurts"}';
      await store.saveWorkoutDraft(document);
      await store.saveWorkoutTerminal(
        sessionId: store.newSessionId(),
        documentJson: document,
      );
      await store.checkpoint();
      final Directory directory = store.openDatabaseFile!.parent;
      _expectMarkerAbsent(directory, 'syn-shoulder-isometric');
      _expectMarkerAbsent(directory, 'This hurts');
    },
  );

  test('a second adaptation pair keeps the first and delete leaves the workout', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    const String sessionId = '11111111-1111-4111-8111-111111111111';
    const String otherId = '22222222-2222-4222-8222-222222222222';
    const String program = '{"record_version":1}';
    const String workout =
        '{"session_id":"11111111-1111-4111-8111-111111111111"}';
    const String readiness =
        '{"soreness":"low","session_id":"11111111-1111-4111-8111-111111111111"}';
    const String adaptation =
        '{"action":"maintain","reason":"Today\'s check keeps the same exercises."}';
    const String later =
        '{"action":"pause_today","reason":"Today\'s check says to wait. The exercises stay the same."}';
    await store.saveProgramRecord(program);
    await store.saveWorkoutTerminal(
      sessionId: sessionId,
      documentJson: workout,
    );
    final int clock = store.clockMillis();
    await store.saveAdaptationPair(
      sessionId: sessionId,
      readinessJson: readiness,
      adaptationJson: adaptation,
      updatedAtMs: clock,
    );
    await expectLater(
      store.saveAdaptationPair(
        sessionId: sessionId,
        readinessJson: readiness,
        adaptationJson: later,
        updatedAtMs: clock,
      ),
      throwsA(anything),
    );
    expect(await store.loadReadinessRecord(sessionId), readiness);
    expect(await store.loadAdaptationRecord(sessionId), adaptation);
    await store.saveWorkoutTerminal(
      sessionId: otherId,
      documentJson: '{"session_id":"$otherId"}',
    );
    final StoredTerminalWorkout? newest = await store
        .loadNewestTerminalWorkout();
    expect(newest?.sessionId, otherId);
    await store.deleteAdaptationPair(sessionId);
    expect(await store.loadReadinessRecord(sessionId), isNull);
    expect(await store.loadAdaptationRecord(sessionId), isNull);
    expect(await store.loadProgramRecord(), program);
    expect(await store.workoutRecordCount(), 2);
  });

  test('workout records stay with the subject that stored them', () async {
    final ProfileStore store = openStore();
    final String first = await store.createProfile();
    const String older = '11111111-1111-4111-8111-111111111111';
    const String newer = '22222222-2222-4222-8222-222222222222';
    await store.saveWorkoutTerminal(
      sessionId: older,
      documentJson: '{"session_id":"$older"}',
    );
    await store.saveWorkoutTerminal(
      sessionId: newer,
      documentJson: '{"session_id":"$newer"}',
    );
    final List<StoredTerminalWorkout> stored = await store.loadWorkoutRecords();
    expect(
      stored.map((StoredTerminalWorkout row) => row.sessionId).toSet(),
      <String>{older, newer},
    );
    expect((await store.loadNewestTerminalWorkout())?.sessionId, newer);

    final String second = await store.createProfile();
    expect(await store.loadWorkoutRecords(), isEmpty);
    expect(await store.loadNewestTerminalWorkout(), isNull);

    await store.switchTo(first);
    expect((await store.loadWorkoutRecords()).length, 2);
    expect((await store.loadNewestTerminalWorkout())?.sessionId, newer);

    await store.switchTo(second);
    expect(await store.loadWorkoutRecords(), isEmpty);
  });

  test('checkpoint hides the progress sentences and rule token', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    await store.saveWorkoutTerminal(
      sessionId: '11111111-1111-4111-8111-111111111111',
      documentJson: '{"session_id":"11111111-1111-4111-8111-111111111111","state":"completed"}',
    );
    await store.checkpoint();
    final Directory directory = store.openDatabaseFile!.parent;
    _expectMarkerAbsent(directory, 'syn-progress-core');
    _expectMarkerAbsent(directory, 'No stored session yet.');
    _expectMarkerAbsent(directory, 'A stored session is on this device.');
    _expectMarkerAbsent(directory, 'The saved sessions could not be read.');
    _expectMarkerAbsent(directory, 'Last stored pain');
    _expectMarkerAbsent(directory, 'Completed sessions');
    _expectMarkerAbsent(directory, 'Abandoned sessions');
    _expectMarkerAbsent(directory, 'Safety stops');
    _expectMarkerAbsent(directory, 'Local progress');
    _expectMarkerAbsent(directory, 'See local progress');
  });

  test(
    'checkpoint removes the soreness token and both reason strings',
    () async {
      final ProfileStore store = openStore();
      await store.createProfile();
      const String sessionId = '11111111-1111-4111-8111-111111111111';
      await store.saveAdaptationPair(
        sessionId: sessionId,
        readinessJson: '{"soreness":"high"}',
        adaptationJson: '{"reason":"Today\'s check says to wait. The exercises stay the same."}',
        updatedAtMs: store.clockMillis(),
      );
      await store.saveAdaptationPair(
        sessionId: '22222222-2222-4222-8222-222222222222',
        readinessJson: '{"soreness":"moderate"}',
        adaptationJson: '{"reason":"Today\'s check keeps the same exercises."}',
        updatedAtMs: store.clockMillis(),
      );
      await store.checkpoint();
      final Directory directory = store.openDatabaseFile!.parent;
      _expectMarkerAbsent(directory, 'high');
      _expectMarkerAbsent(directory, 'moderate');
      _expectMarkerAbsent(
        directory,
        'Today\'s check says to wait. The exercises stay the same.',
      );
      _expectMarkerAbsent(
        directory,
        'Today\'s check keeps the same exercises.',
      );
    },
  );

  test('a flare envelope inserts once and checkpoint hides its tokens', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    const String sessionId = '11111111-1111-4111-8111-111111111111';
    const String otherId = '22222222-2222-4222-8222-222222222222';
    const String readiness = '{"soreness":"low"}';
    const String adaptation = '{"action":"maintain"}';
    const String first =
        '{"choice":"worse_today","action":"keep_program","reason":"Today\'s check keeps the same exercises.","other":"settled","pause":"Today\'s check says to wait. The exercises stay the same."}';
    const String later = '{"choice":"settled"}';
    await store.saveAdaptationPair(
      sessionId: sessionId,
      readinessJson: readiness,
      adaptationJson: adaptation,
      updatedAtMs: store.clockMillis(),
    );
    await store.saveFlareFollowup(
      sessionId: sessionId,
      documentJson: first,
      updatedAtMs: store.clockMillis(),
    );
    await expectLater(
      store.saveFlareFollowup(
        sessionId: sessionId,
        documentJson: later,
        updatedAtMs: store.clockMillis(),
      ),
      throwsA(anything),
    );
    expect(await store.loadFlareFollowup(sessionId), first);
    expect(await store.loadReadinessRecord(sessionId), readiness);
    await store.deleteFlareFollowup(sessionId);
    expect(await store.loadFlareFollowup(sessionId), isNull);
    expect(await store.loadReadinessRecord(sessionId), readiness);
    expect(await store.loadAdaptationRecord(sessionId), adaptation);
    await store.saveFlareFollowup(
      sessionId: otherId,
      documentJson: first,
      updatedAtMs: store.clockMillis(),
    );
    await store.checkpoint();
    final Directory directory = store.openDatabaseFile!.parent;
    _expectMarkerAbsent(directory, 'worse_today');
    _expectMarkerAbsent(directory, 'settled');
    _expectMarkerAbsent(directory, 'keep_program');
    _expectMarkerAbsent(
      directory,
      'Today\'s check says to wait. The exercises stay the same.',
    );
    _expectMarkerAbsent(directory, 'Today\'s check keeps the same exercises.');
  });

  test('appearance choice stays with the subject that saved it', () async {
    final ProfileStore store = openStore();
    final String first = await store.createProfile();
    expect(await store.loadAppearanceChoice(), isNull);
    await store.saveAppearanceChoice('dark');
    expect(await store.loadAppearanceChoice(), 'dark');
    final int expected = DateTime.utc(
      2026,
      1,
      2,
      3,
      4,
      5,
    ).millisecondsSinceEpoch;
    final String keyHex = (await store.keys.read(profileKeyItem(first)))!;
    final File file = store.openDatabaseFile!;
    await store.checkpoint();
    await store.close();
    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    final ResultSet rows = raw.select(
      'SELECT choice, updated_at_ms FROM appearance_records',
    );
    expect(rows.first.columnAt(0), 'dark');
    expect(rows.first.columnAt(1), expected);
    raw.close();

    await store.reopenActive();
    final String second = await store.createProfile();
    expect(second, isNot(first));
    expect(await store.loadAppearanceChoice(), isNull);
    await store.saveAppearanceChoice('light');
    expect(await store.loadAppearanceChoice(), 'light');
    await store.switchTo(first);
    expect(await store.loadAppearanceChoice(), 'dark');
    await store.switchTo(second);
    expect(await store.loadAppearanceChoice(), 'light');
    await expectLater(
      store.saveAppearanceChoice('sepia'),
      throwsA(
        isA<StorageSchemaException>().having(
          (StorageSchemaException error) => error.message,
          'message',
          'appearance choice is not supported',
        ),
      ),
    );
    expect(await store.loadAppearanceChoice(), 'light');
  });

  test('appearance choice requires an active profile', () async {
    final ProfileStore store = openStore();
    await expectLater(
      store.loadAppearanceChoice(),
      throwsA(
        isA<StorageIoException>().having(
          (StorageIoException error) => error.message,
          'message',
          'no active profile',
        ),
      ),
    );
    await expectLater(
      store.saveAppearanceChoice('system'),
      throwsA(
        isA<StorageIoException>().having(
          (StorageIoException error) => error.message,
          'message',
          'no active profile',
        ),
      ),
    );
  });

  test('checkpoint hides the privacy sentences', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    await store.saveAppearanceChoice('dark');
    await store.checkpoint();
    final Directory directory = store.openDatabaseFile!.parent;
    _expectMarkerAbsent(directory, 'This profile stays on this device.');
    _expectMarkerAbsent(directory, 'The profile database is encrypted.');
    _expectMarkerAbsent(directory, 'Cloud sync is not connected.');
    _expectMarkerAbsent(directory, 'No AI coach is active.');
    _expectMarkerAbsent(directory, 'Privacy and appearance');
    _expectMarkerAbsent(directory, 'The saved appearance could not be read.');
    expect(await store.loadAppearanceChoice(), 'dark');
  });

  test('problem report requires an active profile', () async {
    final ProfileStore store = openStore();
    await expectLater(
      store.saveProblemReport(category: 'app_issue', note: ''),
      throwsA(
        isA<StorageIoException>().having(
          (StorageIoException error) => error.message,
          'message',
          allOf(equals('no active profile'), isNot('no open database')),
        ),
      ),
    );
  });

  test('unknown category and a long note insert nothing', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    await expectLater(
      store.saveProblemReport(category: 'sepia', note: 'ok'),
      throwsA(
        isA<StorageSchemaException>().having(
          (StorageSchemaException error) => error.message,
          'message',
          'report category is not supported',
        ),
      ),
    );
    await expectLater(
      store.saveProblemReport(category: 'app_issue', note: 'a' * 501),
      throwsA(
        isA<StorageSchemaException>().having(
          (StorageSchemaException error) => error.message,
          'message',
          'note is too long',
        ),
      ),
    );
    expect(await _problemReportCount(store), 0);
  });

  test('a problem report round-trips category note clock and id', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    final String reportId = await store.saveProblemReport(
      category: 'app_issue',
      note: 'shoulder note',
    );
    final StoredProblemReport report = (await store.loadProblemReport(
      reportId,
    ))!;
    expect(report.reportId, reportId);
    expect(report.category, 'app_issue');
    expect(report.note, 'shoulder note');
    expect(
      report.createdAtMs,
      DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch,
    );
    expect(
      report.reportId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test(
    'a stored program copies rule columns and leaves exercise null',
    () async {
      final ProfileStore store = openStore();
      await store.createProfile();
      await store.saveProgramRecord(_validProgram);
      final String reportId = await store.saveProblemReport(
        category: 'app_issue',
        note: 'shoulder note',
      );
      final StoredProblemReport report = (await store.loadProblemReport(
        reportId,
      ))!;
      expect(report.programRecordVersion, 1);
      expect(report.programRuleId, 'syn-program-core');
      expect(report.programRuleVersion, 1);
      expect(report.safetyRuleId, 'syn-safety-core');
      expect(report.safetyRuleVersion, 1);
      expect(report.exerciseId, isNull);
      expect(report.exerciseVersion, isNull);
    },
  );

  test('a known exercise id copies that exercise version', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    await store.saveProgramRecord(_validProgram);
    final String reportId = await store.saveProblemReport(
      category: 'exercise_instruction',
      note: '',
      exerciseId: 'syn-shoulder-isometric',
    );
    final StoredProblemReport report = (await store.loadProblemReport(
      reportId,
    ))!;
    expect(report.exerciseId, 'syn-shoulder-isometric');
    expect(report.exerciseVersion, 1);
    expect(report.programRuleId, 'syn-program-core');
    expect(report.programRuleVersion, 1);
    expect(report.safetyRuleId, 'syn-safety-core');
    expect(report.safetyRuleVersion, 1);
  });

  test('an exercise id without a readable program inserts nothing', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    const String bad = '{"not":"a program"}';
    await store.saveProgramRecord(bad);
    await expectLater(
      store.saveProblemReport(
        category: 'app_issue',
        note: '',
        exerciseId: 'syn-shoulder-isometric',
      ),
      throwsA(
        isA<StorageSchemaException>().having(
          (StorageSchemaException error) => error.message,
          'message',
          'stored program could not be read',
        ),
      ),
    );
    expect(await store.loadProgramRecord(), bad);
    expect(await _problemReportCount(store), 0);
  });

  test('an unknown exercise id inserts nothing', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    await store.saveProgramRecord(_validProgram);
    await expectLater(
      store.saveProblemReport(
        category: 'app_issue',
        note: '',
        exerciseId: 'nope',
      ),
      throwsA(
        isA<StorageSchemaException>().having(
          (StorageSchemaException error) => error.message,
          'message',
          'exercise is not in the stored program',
        ),
      ),
    );
    expect(await store.loadProgramRecord(), _validProgram);
    expect(await _problemReportCount(store), 0);
  });

  test('a missing session id inserts nothing', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    const String sessionId = '11111111-1111-4111-8111-111111111111';
    await expectLater(
      store.saveProblemReport(
        category: 'app_issue',
        note: '',
        sessionId: sessionId,
      ),
      throwsA(
        isA<StorageSchemaException>().having(
          (StorageSchemaException error) => error.message,
          'message',
          'session is not stored',
        ),
      ),
    );
    expect(await _problemReportCount(store), 0);
  });

  test('an unreadable program still saves with null version columns', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    const String bad = '{"not":"a program"}';
    await store.saveProgramRecord(bad);
    final String reportId = await store.saveProblemReport(
      category: 'content_issue',
      note: '',
    );
    final StoredProblemReport report = (await store.loadProblemReport(
      reportId,
    ))!;
    expect(report.programRecordVersion, isNull);
    expect(report.programRuleId, isNull);
    expect(report.programRuleVersion, isNull);
    expect(report.safetyRuleId, isNull);
    expect(report.safetyRuleVersion, isNull);
    expect(report.exerciseId, isNull);
    expect(report.exerciseVersion, isNull);
    expect(await store.loadProgramRecord(), bad);
  });

  test('a second subject does not load the first report', () async {
    final ProfileStore store = openStore();
    final String first = await store.createProfile();
    final String reportId = await store.saveProblemReport(
      category: 'app_issue',
      note: 'kept',
    );
    final String second = await store.createProfile();
    expect(second, isNot(first));
    expect(await store.loadProblemReport(reportId), isNull);
    await store.switchTo(first);
    expect((await store.loadProblemReport(reportId))!.note, 'kept');
  });

  test('checkpoint hides a problem report note', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    const String marker = 'helpmemove-report-note-marker';
    await store.saveProblemReport(category: 'app_issue', note: marker);
    await store.checkpoint();
    final Directory directory = store.openDatabaseFile!.parent;
    _expectMarkerAbsent(directory, marker);
    final String subjectId = (await store.keys.read(activeProfileItem))!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    final File file = store.openDatabaseFile!;
    await store.close();
    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    expect(
      raw.select('SELECT note FROM problem_report_records').first.columnAt(0),
      marker,
    );
    raw.close();
  });

  test('an invalid subject never becomes a path', () async {
    final ProfileStore store = openStore();
    await expectLater(
      store.switchTo('Not A Subject'),
      throwsA(isA<BridgeError>()),
    );
    expect(temp.listSync(recursive: true), isEmpty);
  });
}

const String _validProgram =
    '{"record_version":1,"rule_id":"syn-program-core","rule_version":1,"safety_rule_id":"syn-safety-core","safety_rule_version":1,"session_minutes":15,"exercises":[{"exercise_id":"syn-shoulder-isometric","exercise_version":1,"regions":["shoulder"],"sets":1,"reps":1,"tempo":{"eccentric":2,"pause":1,"concentric":2},"reasons":[{"code":"region_match","region":"shoulder","equipment":null,"goal":null},{"code":"equipment_match","region":null,"equipment":"bodyweight","goal":null},{"code":"goal_match","region":null,"equipment":null,"goal":"control"},{"code":"screen_clear","region":null,"equipment":null,"goal":null},{"code":"fixture_defaults","region":null,"equipment":null,"goal":null}]}]}';

Future<Object?> _problemReportCount(ProfileStore store) async {
  final String subjectId = (await store.keys.read(activeProfileItem))!;
  final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
  final File file = store.openDatabaseFile!;
  await store.close();
  final Database raw = sqlite3.open(file.path);
  applyEncryptionSetup(raw, keyHex);
  final Object? count = raw
      .select('SELECT COUNT(*) FROM problem_report_records')
      .first
      .columnAt(0);
  raw.close();
  return count;
}

bool _startsWithSqliteHeader(File file) {
  final List<int> header = file.readAsBytesSync().take(16).toList();
  const List<int> magic = <int>[
    0x53,
    0x51,
    0x4c,
    0x69,
    0x74,
    0x65,
    0x20,
    0x66,
    0x6f,
    0x72,
    0x6d,
    0x61,
    0x74,
    0x20,
    0x33,
    0x00,
  ];
  if (header.length < magic.length) {
    return false;
  }
  for (int index = 0; index < magic.length; index++) {
    if (header[index] != magic[index]) {
      return false;
    }
  }
  return true;
}

void _expectMarkerAbsent(Directory directory, String marker) {
  final List<int> needle = utf8.encode(marker);
  for (final FileSystemEntity entity in directory.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final List<int> bytes = entity.readAsBytesSync();
    expect(_containsBytes(bytes, needle), isFalse, reason: entity.path);
  }
}

void _expectNoProbeMarker(Directory directory) {
  const String marker = storageProbePayload;
  final List<int> needle = marker.codeUnits;
  for (final FileSystemEntity entity in directory.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final List<int> bytes = entity.readAsBytesSync();
    expect(_containsBytes(bytes, needle), isFalse, reason: entity.path);
  }
}

bool _containsBytes(List<int> bytes, List<int> needle) {
  if (needle.isEmpty || bytes.length < needle.length) {
    return false;
  }
  for (int start = 0; start <= bytes.length - needle.length; start++) {
    var matched = true;
    for (int offset = 0; offset < needle.length; offset++) {
      if (bytes[start + offset] != needle[offset]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return true;
    }
  }
  return false;
}
