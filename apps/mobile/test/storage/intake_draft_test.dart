import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/intake/intake_draft.dart';
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
    temp = Directory.systemTemp.createTempSync('helpmemove-intake');
  });

  tearDown(() async {
    await live?.close();
    live = null;
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  ProfileStore openStore() {
    final ProfileStore store = ProfileStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(7),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    return store;
  }

  test(
    'draft round-trips, replaces, and deletes in the encrypted file',
    () async {
      final ProfileStore store = openStore();
      final String subjectId = await store.createProfile();
      final LocalIntakeDraft draft = LocalIntakeDraft(
        intent: 'fitness',
        noticeId: 'syn-notice-1',
        schemaAck: 'yes',
        goals: <String>['strength'],
        equipment: <String>['mat'],
        areas: const <IntakeArea>[
          IntakeArea(region: 'leg', laterality: 'left'),
        ],
        note: 'local only',
        severity: 3,
        step: 'check',
      );
      final String first = draft.encode();
      await store.saveDraft(first);
      final LocalIntakeDraft again = LocalIntakeDraft(
        intent: 'not_sure',
        step: 'intent',
      );
      final String second = again.encode();
      await store.saveDraft(second);

      final File file = store.openDatabaseFile!;
      final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
      await store.close();

      final ProfileDatabase database = ProfileDatabase.open(
        file: file,
        keyHex: keyHex,
      );
      final rows = await database
          .customSelect(
            'SELECT document_json, updated_at_ms FROM intake_drafts',
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('document_json'), second);
      expect(
        rows.single.read<int>('updated_at_ms'),
        DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch,
      );
      await database.close();

      expect(await store.openActive(), '/');
      final String? loaded = await store.loadDraft();
      expect(loaded, second);
      final LocalIntakeDraft decoded = LocalIntakeDraft.decode(loaded!);
      expect(decoded.intent, 'not_sure');
      expect(decoded.note, '');
      await store.deleteDraft();
      expect(await store.loadDraft(), isNull);
      await store.close();
      expect(await store.openActive(), '/');
      expect(await store.loadDraft(), isNull);
    },
  );

  test('schema 1 opened by schema 3 is rejected', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final File file = store.openDatabaseFile!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    await store.close();

    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    raw.execute('DROP TABLE IF EXISTS assessment_drafts');
    raw.execute('DROP TABLE IF EXISTS assessment_records');
    raw.execute('DROP TABLE IF EXISTS intake_drafts');
    raw.execute('PRAGMA user_version = 1');
    raw.close();

    await expectLater(
      store.reopenActive(),
      throwsA(isA<StorageSchemaException>()),
    );

    final Database again = sqlite3.open(file.path);
    applyEncryptionSetup(again, keyHex);
    expect(again.select('PRAGMA user_version').first.columnAt(0), 1);
    expect(
      again.select('SELECT payload_text FROM local_events').first.columnAt(0),
      storageProbePayload,
    );
    final ResultSet tables = again.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'intake_drafts'",
    );
    expect(tables, isEmpty);
    again.close();
  });

  test(
    'checkpoint leaves the note bytes out of the profile directory',
    () async {
      const String marker = 'hmm-intake-note-7f3c9a';
      final ProfileStore store = openStore();
      await store.createProfile();
      await store.saveDraft(
        LocalIntakeDraft(note: marker, step: 'note').encode(),
      );
      await store.checkpoint();
      final Directory directory = store.openDatabaseFile!.parent;
      final List<int> needle = utf8.encode(marker);
      for (final FileSystemEntity entity in directory.listSync(
        recursive: true,
      )) {
        if (entity is! File) {
          continue;
        }
        final List<int> bytes = entity.readAsBytesSync();
        expect(_containsBytes(bytes, needle), isFalse, reason: entity.path);
      }
      final String? loaded = await store.loadDraft();
      expect(LocalIntakeDraft.decode(loaded!).note, marker);
    },
  );

  test('draft codec rejects extra keys, long notes, and duplicate regions', () {
    final LocalIntakeDraft draft = LocalIntakeDraft(note: 'n' * 201);
    expect(draft.encode, throwsA(isA<LocalIntakeDraftException>()));

    const String extra =
        '{"draft_version":1,"intent":null,"notice_id":null,"schema_ack":null,"goals":[],"equipment":[],"areas":[],"note":"","severity":0,"step":"intent","age":4}';
    expect(
      () => LocalIntakeDraft.decode(extra),
      throwsA(isA<LocalIntakeDraftException>()),
    );

    const String duplicate =
        '{"draft_version":1,"intent":null,"notice_id":null,"schema_ack":null,"goals":[],"equipment":[],"areas":[{"region":"arm","laterality":"left"},{"region":"arm","laterality":"right"}],"note":"","severity":0,"step":"body"}';
    expect(
      () => LocalIntakeDraft.decode(duplicate),
      throwsA(isA<LocalIntakeDraftException>()),
    );
    expect(extra.contains('age'), isTrue);
  });
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
