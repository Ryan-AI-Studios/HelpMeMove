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
  if (rows.isEmpty) {
    throw const StorageCipherUnavailable();
  }
  final Object? cipher = rows.first.columnAt(0);
  if (cipher == null || cipher.toString().isEmpty) {
    throw const StorageCipherUnavailable();
  }
  database.execute('PRAGMA secure_delete = ON');
}
