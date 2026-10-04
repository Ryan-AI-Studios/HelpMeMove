import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'package:helpmemove/storage/backup_channel.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';

class StorageController {
  StorageController({required this.buildStore});

  final Future<ProfileStore> Function() buildStore;
  ProfileStore? _store;

  ProfileStore? get store => _store;

  factory StorageController.production() {
    return StorageController(
      buildStore: () async {
        final Directory support = await getApplicationSupportDirectory();
        return ProfileStore(
          keys: SecureProfileKeyStore(productionSecureStorage()),
          supportDirectory: support,
          clock: DateTime.now,
          random: Random.secure(),
          excludeFromBackup: excludeFromBackupOnIos,
        );
      },
    );
  }

  Future<String> open() async {
    try {
      _store ??= await buildStore();
      return await _store!.openActive();
    } on StorageKeyLoss {
      return '/key-loss';
    } catch (_) {
      return '/storage-failure';
    }
  }

  Future<String> reset() async {
    final ProfileStore? store = _store;
    if (store == null) {
      return open();
    }
    try {
      return await store.resetActive();
    } on StorageKeyLoss {
      return '/key-loss';
    } catch (_) {
      return '/storage-failure';
    }
  }
}
