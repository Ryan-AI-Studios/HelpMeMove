import 'dart:async';
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
  Future<void>? _queue;
  Future<String>? _inflightOpen;

  Future<T> _queued<T>(Future<T> Function() action) async {
    final Completer<void> turn = Completer<void>();
    final Future<void>? earlier = _queue;
    _queue = turn.future;
    if (earlier != null) {
      await earlier;
    }
    try {
      return await action();
    } finally {
      turn.complete();
    }
  }

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

  Future<String> open() {
    final Future<String>? inflight = _inflightOpen;
    if (inflight != null) {
      return inflight;
    }
    final Future<String> current = _queued(_open);
    _inflightOpen = current;
    current.whenComplete(() {
      if (identical(_inflightOpen, current)) {
        _inflightOpen = null;
      }
    });
    return current;
  }

  Future<String> _open() async {
    try {
      _store ??= await buildStore();
      return await _store!.openActive();
    } on StorageKeyLoss {
      return '/key-loss';
    } catch (_) {
      return '/storage-failure';
    }
  }

  Future<String> reset() => _queued(_reset);

  Future<String> _reset() async {
    final ProfileStore? store = _store;
    if (store == null) {
      return _open();
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
