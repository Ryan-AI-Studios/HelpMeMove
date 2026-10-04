import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class ProfileKeyStore {
  Future<String?> read(String item);

  Future<void> write(String item, String value);

  Future<void> delete(String item);
}

class MemoryProfileKeyStore implements ProfileKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String item) async => values[item];

  @override
  Future<void> write(String item, String value) async {
    values[item] = value;
  }

  @override
  Future<void> delete(String item) async {
    values.remove(item);
  }
}

class SecureProfileKeyStore implements ProfileKeyStore {
  SecureProfileKeyStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String item) => _storage.read(key: item);

  @override
  Future<void> write(String item, String value) =>
      _storage.write(key: item, value: value);

  @override
  Future<void> delete(String item) => _storage.delete(key: item);
}

const AndroidOptions productionAndroidOptions = AndroidOptions(
  resetOnError: false,
  enforceBiometrics: false,
  storageNamespace: 'helpmemove',
);

const IOSOptions productionIosOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
  synchronizable: false,
);

FlutterSecureStorage productionSecureStorage() {
  return const FlutterSecureStorage(
    aOptions: productionAndroidOptions,
    iOptions: productionIosOptions,
  );
}
