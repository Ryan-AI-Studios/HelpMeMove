import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-export');
  });

  tearDown(() async {
    await live?.close();
    live = null;
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  ProfileStore openStore({
    ProfileKeyStore? keys,
    DateTime Function()? clock,
    Future<void> Function(String path)? excludeFromBackup,
  }) {
    final ProfileStore store = ProfileStore(
      keys: keys ?? MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: clock ?? () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(11),
      excludeFromBackup: excludeFromBackup ?? (String path) async {},
    );
    live = store;
    return store;
  }

  Directory profileDirectory(String subjectId) {
    return Directory(
      '${temp.path}${Platform.pathSeparator}profiles'
      '${Platform.pathSeparator}$subjectId',
    );
  }

  File exportFile(String subjectId) {
    return File(
      '${profileDirectory(subjectId).path}${Platform.pathSeparator}export.json',
    );
  }

  test('deleteExport ignores a null target and a missing file', () async {
    final ProfileStore store = openStore();
    await store.deleteExport();
    await store.deleteExport('not-a-real-subject');
    final String subjectId = await store.createProfile();
    await store.deleteExport();
    expect(exportFile(subjectId).existsSync(), isFalse);
  });

  test('records keep order and document_json is the stored text', () async {
    final int created = DateTime.utc(2026, 1, 2).millisecondsSinceEpoch;
    var millis = created;
    final ProfileStore store = openStore(
      clock: () => DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
    );
    final String subjectId = await store.createProfile();
    const String assessment = '{"keep":"quote \\" and slash \\\\"}';
    const String program = '{"plan":"one"}';
    millis = created + 2000;
    await store.saveWorkoutTerminal(
      sessionId: 'sess-z',
      documentJson: '{"session_id":"sess-z"}',
    );
    millis = created + 1000;
    await store.saveWorkoutTerminal(
      sessionId: 'sess-a',
      documentJson: '{"session_id":"sess-a"}',
    );
    await store.saveAssessmentRecord(assessment);
    await store.saveProgramRecord(program);
    await store.saveDraft('{"draft":true}');
    await store.saveAppearanceChoice('dark');
    millis = created + 10000;
    await store.reopenActive();
    await store.writeExport();

    final File file = exportFile(subjectId);
    final String text = file.readAsStringSync();
    final Map<String, Object?> root = jsonDecode(text) as Map<String, Object?>;
    expect(root.keys.toList(), <String>['subject_id', 'records']);
    expect(root['subject_id'], subjectId);
    final List<Object?> records = root['records']! as List<Object?>;
    final List<String> tables = <String>[
      for (final Object? row in records)
        (row! as Map<String, Object?>)['table']! as String,
    ];
    expect(tables, <String>[
      'local_profiles',
      'assessment_records',
      'program_records',
      'workout_records',
      'workout_records',
    ]);
    final Map<String, Object?> profile = records[0]! as Map<String, Object?>;
    expect(profile.containsKey('document_json'), isFalse);
    expect(profile['created_at_ms'], isA<int>());
    expect(profile['last_active_at_ms'], created + 10000);
    expect(
      profile['last_active_at_ms'] as int,
      greaterThan(profile['created_at_ms'] as int),
    );
    final Map<String, Object?> assessmentRow =
        records[1]! as Map<String, Object?>;
    expect(assessmentRow['document_json'], assessment);
    expect(text.contains('"document_json":"'), isTrue);
    expect(RegExp(r'"document_json"\s*:\s*\{').hasMatch(text), isFalse);
    final Map<String, Object?> firstWorkout =
        records[3]! as Map<String, Object?>;
    final Map<String, Object?> secondWorkout =
        records[4]! as Map<String, Object?>;
    expect(firstWorkout['session_id'], 'sess-a');
    expect(secondWorkout['session_id'], 'sess-z');
    expect(text.contains('intake_drafts'), isFalse);
    expect(text.contains('assessment_drafts'), isFalse);
    expect(text.contains('workout_drafts'), isFalse);
    expect(text.contains('readiness_records'), isFalse);
    expect(text.contains('adaptation_records'), isFalse);
    expect(text.contains('flare_followup_records'), isFalse);
    expect(text.contains('appearance_records'), isFalse);
    expect(text.contains('local_events'), isFalse);
    expect(text.contains('sync_outbox'), isFalse);
  });

  test('a second subject and a problem report stay out of the file', () async {
    final ProfileStore store = openStore();
    final String first = await store.createProfile();
    await store.saveAssessmentRecord('{"who":"first-subject"}');
    final String second = await store.createProfile();
    await store.saveAssessmentRecord('{"who":"second-subject"}');
    final String reportId = await store.saveProblemReport(
      category: 'app_issue',
      note: 'secret-report-note',
    );
    expect(reportId, isNotEmpty);
    await store.writeExport();
    final String text = exportFile(second).readAsStringSync();
    expect(text.contains(first), isFalse);
    expect(text.contains('first-subject'), isFalse);
    expect(text.contains('problem_report_records'), isFalse);
    expect(text.contains('secret-report-note'), isFalse);
    expect(text.contains('second-subject'), isTrue);
  });

  test('a thrown write deletes the partial file', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    store.onBeforeExportWrite = (File file) async {
      file.writeAsStringSync('{"partial":', flush: true);
      throw StateError('partial write');
    };
    await expectLater(store.writeExport(), throwsA(isA<StateError>()));
    expect(exportFile(subjectId).existsSync(), isFalse);
  });

  test(
    'excludeFromBackup throws after the file exists and deletes it',
    () async {
      String? excluded;
      final ProfileStore store = openStore(
        excludeFromBackup: (String path) async {
          final File file = File('$path${Platform.pathSeparator}export.json');
          if (file.existsSync()) {
            excluded = path;
            throw StateError('exclude failed');
          }
        },
      );
      final String subjectId = await store.createProfile();
      await expectLater(store.writeExport(), throwsA(isA<StateError>()));
      expect(excluded, profileDirectory(subjectId).path);
      expect(exportFile(subjectId).existsSync(), isFalse);
    },
  );

  test('writeExport throws when no profile is open', () async {
    final ProfileStore store = openStore();
    await expectLater(
      store.writeExport(),
      throwsA(
        isA<StorageIoException>().having(
          (StorageIoException error) => error.message,
          'message',
          'no open database',
        ),
      ),
    );
  });

  test('openActive removes a leftover export.json', () async {
    final ProfileKeyStore keys = MemoryProfileKeyStore();
    final ProfileStore store = openStore(keys: keys);
    final String subjectId = await store.createProfile();
    await store.writeExport();
    expect(exportFile(subjectId).existsSync(), isTrue);
    await store.close();
    expect(await store.openActive(), '/');
    expect(exportFile(subjectId).existsSync(), isFalse);
  });

  test('openActive removes export.json before key-loss', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    await store.writeExport();
    await store.keys.delete(profileKeyItem(subjectId));
    await store.close();
    expect(await store.openActive(), '/key-loss');
    expect(exportFile(subjectId).existsSync(), isFalse);
  });

  test('openActive removes export.json before storage-failure', () async {
    final ProfileKeyStore keys = MemoryProfileKeyStore();
    final ProfileStore first = openStore(keys: keys);
    final String subjectId = await first.createProfile();
    await first.writeExport();
    await first.close();
    live = null;
    final ProfileStore second = openStore(
      keys: keys,
      excludeFromBackup: (String path) async {
        throw StateError('backup exclusion failed');
      },
    );
    expect(await second.openActive(), '/storage-failure');
    expect(exportFile(subjectId).existsSync(), isFalse);
  });

  test('a thrown deleteExport does not change the openActive route', () async {
    final _ThrowingDeleteStore store = _ThrowingDeleteStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2),
      random: Random(3),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await store.createProfile();
    await store.close();
    expect(await store.openActive(), '/');
  });

  test(
    'removeSubjectDirectoryFirst closes, then deletes only that directory',
    () async {
      final ProfileStore store = openStore();
      final String first = await store.createProfile();
      final String second = await store.createProfile();
      var closedWhilePresent = false;
      store.onDatabaseClosed = () {
        closedWhilePresent = profileDirectory(second).existsSync();
      };
      final LocalRemoval removal = await store.removeSubjectDirectoryFirst(
        second,
      );
      expect(removal, LocalRemoval.replaced);
      expect(closedWhilePresent, isTrue);
      expect(profileDirectory(second).existsSync(), isFalse);
      expect(profileDirectory(first).existsSync(), isTrue);
      expect(store.activeSubjectId, isNot(second));
      expect(store.hasOpenDatabase, isTrue);
      expect(await store.keys.read(profileKeyItem(second)), isNull);
    },
  );

  test('a failed directory delete leaves the key', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    store.onBeforeDirectoryDelete = () async {
      throw StateError('directory locked');
    };
    final LocalRemoval removal = await store.removeSubjectDirectoryFirst(
      subjectId,
    );
    expect(removal, LocalRemoval.directoryRemained);
    expect(await store.keys.read(profileKeyItem(subjectId)), isNotNull);
    expect(store.activeSubjectId, subjectId);
    expect(profileDirectory(subjectId).existsSync(), isTrue);
  });

  test('a failed reopen still returns directoryRemained', () async {
    final _ReadFails keys = _ReadFails(MemoryProfileKeyStore());
    final ProfileStore store = openStore(keys: keys);
    final String subjectId = await store.createProfile();
    store.onBeforeDirectoryDelete = () async {
      throw StateError('directory locked');
    };
    keys.failReads = true;
    final LocalRemoval removal = await store.removeSubjectDirectoryFirst(
      subjectId,
    );
    expect(removal, LocalRemoval.directoryRemained);
    expect(await keys.inner.read(profileKeyItem(subjectId)), isNotNull);
  });

  test(
    'a key delete throw after the directory is gone still creates a profile',
    () async {
      final _DeleteFails keys = _DeleteFails(MemoryProfileKeyStore());
      final ProfileStore store = openStore(keys: keys);
      final String subjectId = await store.createProfile();
      keys.failProfileKey = true;
      final LocalRemoval removal = await store.removeSubjectDirectoryFirst(
        subjectId,
      );
      expect(removal, LocalRemoval.replaced);
      expect(profileDirectory(subjectId).existsSync(), isFalse);
      expect(store.activeSubjectId, isNot(subjectId));
      expect(store.hasOpenDatabase, isTrue);
    },
  );

  test('a pointer delete throw still creates a profile', () async {
    final _DeleteFails keys = _DeleteFails(MemoryProfileKeyStore());
    final ProfileStore store = openStore(keys: keys);
    final String subjectId = await store.createProfile();
    keys.failActivePointer = true;
    final LocalRemoval removal = await store.removeSubjectDirectoryFirst(
      subjectId,
    );
    expect(removal, LocalRemoval.replaced);
    expect(profileDirectory(subjectId).existsSync(), isFalse);
    expect(store.hasOpenDatabase, isTrue);
  });

  test('createProfile failure returns notReplaced', () async {
    final _FailCreateStore store = _FailCreateStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2),
      random: Random(5),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    final String subjectId = await store.createProfile();
    store.failCreate = true;
    final LocalRemoval removal = await store.removeSubjectDirectoryFirst(
      subjectId,
    );
    expect(removal, LocalRemoval.notReplaced);
    expect(profileDirectory(subjectId).existsSync(), isFalse);
    expect(store.hasOpenDatabase, isFalse);
  });
}

class _ThrowingDeleteStore extends ProfileStore {
  _ThrowingDeleteStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  @override
  Future<void> deleteExport([String? subjectId]) async {
    throw StateError('delete export');
  }
}

class _FailCreateStore extends ProfileStore {
  _FailCreateStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  bool failCreate = false;

  @override
  Future<String> createProfile() {
    if (failCreate) {
      throw const StorageIoException('create failed');
    }
    return super.createProfile();
  }
}

class _ReadFails implements ProfileKeyStore {
  _ReadFails(this.inner);

  final MemoryProfileKeyStore inner;
  bool failReads = false;

  @override
  Future<String?> read(String item) async {
    if (failReads) {
      throw const FileSystemException('read failed');
    }
    return inner.read(item);
  }

  @override
  Future<void> write(String item, String value) => inner.write(item, value);

  @override
  Future<void> delete(String item) => inner.delete(item);
}

class _DeleteFails implements ProfileKeyStore {
  _DeleteFails(this.inner);

  final MemoryProfileKeyStore inner;
  bool failProfileKey = false;
  bool failActivePointer = false;

  @override
  Future<String?> read(String item) => inner.read(item);

  @override
  Future<void> write(String item, String value) => inner.write(item, value);

  @override
  Future<void> delete(String item) async {
    if (failProfileKey && item.startsWith('profile-key.')) {
      throw const FileSystemException('key delete');
    }
    if (failActivePointer && item == activeProfileItem) {
      throw const FileSystemException('pointer delete');
    }
    await inner.delete(item);
  }
}
