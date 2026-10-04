import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/encryption.dart';
import 'package:helpmemove/storage/profile_database.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';

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
