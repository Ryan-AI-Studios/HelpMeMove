/// Encryption support is missing, so the database must not open.
class StorageCipherUnavailable implements Exception {
  const StorageCipherUnavailable();

  @override
  String toString() => 'StorageCipherUnavailable';
}

/// The device key for the active local profile is missing.
class StorageKeyLoss implements Exception {
  const StorageKeyLoss();

  @override
  String toString() => 'StorageKeyLoss';
}

/// The on-disk schema is not schema version 1.
class StorageSchemaException implements Exception {
  const StorageSchemaException(this.message);

  final String message;

  @override
  String toString() => 'StorageSchemaException: $message';
}

/// The local database could not be read or written.
class StorageIoException implements Exception {
  const StorageIoException(this.message);

  final String message;

  @override
  String toString() => 'StorageIoException: $message';
}
