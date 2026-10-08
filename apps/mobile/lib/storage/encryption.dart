import 'package:sqlite3/sqlite3.dart';

import 'package:helpmemove/storage/storage_exception.dart';

final RegExp profileKeyHex = RegExp(r'^[0-9a-f]{64}$');

/// Applies the validated raw key and refuses a build without a cipher.
void applyEncryptionSetup(Database database, String keyHex) {
  if (!profileKeyHex.hasMatch(keyHex)) {
    throw const StorageIoException('rejected database key');
  }
  database.execute('PRAGMA key = "x\'$keyHex\'"');
  final ResultSet rows = database.select('PRAGMA cipher');
  rejectEmptyCipher(
    hasRow: rows.isNotEmpty,
    cipher: rows.isEmpty ? null : rows.first.columnAt(0),
  );
  database.execute('PRAGMA secure_delete = ON');
}

/// Refuses a build that did not report a cipher. Release builds strip `assert`.
void rejectEmptyCipher({required bool hasRow, required Object? cipher}) {
  if (!hasRow || cipher == null || cipher.toString().isEmpty) {
    throw const StorageCipherUnavailable();
  }
}
