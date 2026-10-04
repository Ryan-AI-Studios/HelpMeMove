import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

  test(
    'schema 3 gains program records and keeps intake and assessment',
    () async {
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

      await store.reopenActive();
      expect(await store.loadDraft(), intake);
      expect(await store.loadAssessmentRecord(), assessment);
      expect(await store.loadProgramRecord(), isNull);
      await store.close();

      final Database upgraded = sqlite3.open(file.path);
      applyEncryptionSetup(upgraded, keyHex);
      expect(upgraded.select('PRAGMA user_version').first.columnAt(0), 4);
      expect(
        upgraded
            .select('SELECT document_json FROM intake_drafts')
            .first
            .columnAt(0),
        intake,
      );
      expect(
        upgraded
            .select('SELECT document_json FROM assessment_records')
            .first
            .columnAt(0),
        assessment,
      );
      final ResultSet tables = upgraded.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'program_records'",
      );
      expect(tables, hasLength(1));
      upgraded.close();
    },
  );

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

  test('an invalid subject never becomes a path', () async {
    final ProfileStore store = openStore();
    await expectLater(
      store.switchTo('Not A Subject'),
      throwsA(isA<BridgeError>()),
    );
    expect(temp.listSync(recursive: true), isEmpty);
  });
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
