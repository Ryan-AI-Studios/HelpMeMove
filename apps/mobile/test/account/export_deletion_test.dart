import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/account/account_auth.dart';
import 'package:helpmemove/account/account_controller.dart';
import 'package:helpmemove/account/account_screen.dart';
import 'package:helpmemove/account/phone_unlock.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-export-account');
    AccountAuth.started = false;
  });

  tearDown(() async {
    AccountAuth.started = false;
    await live?.close();
    live = null;
    if (temp.existsSync()) {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // A locked hold file is closed in the test that opened it.
      }
    }
  });

  ProfileStore openStore({
    ProfileKeyStore? keys,
    Future<void> Function(String path)? excludeFromBackup,
  }) {
    final ProfileStore store = ProfileStore(
      keys: keys ?? MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 8),
      random: Random(7),
      excludeFromBackup: excludeFromBackup ?? (String path) async {},
    );
    live = store;
    return store;
  }

  File exportFile(String subjectId) {
    return File(
      '${temp.path}${Platform.pathSeparator}profiles'
      '${Platform.pathSeparator}$subjectId'
      '${Platform.pathSeparator}export.json',
    );
  }

  AccountController accountFor(
    ProfileStore store, {
    PhoneUnlock? phoneUnlock,
    bool Function()? sessionReady,
    DeleteRpc? deleteRpc,
    SignOutAction? signOutAction,
    StopRefresh? stopRefresh,
  }) {
    return AccountController(
      store: store,
      phoneUnlock: phoneUnlock ?? _ScriptedUnlock(),
      sessionReady: sessionReady ?? () => false,
      deleteRpc: deleteRpc ?? () async => 'unavailable',
      signOutAction: signOutAction ?? () async {},
      stopRefresh: stopRefresh ?? () {},
    );
  }

  test(
    'production delete helpers return before Supabase when auth is off',
    () async {
      expect(AccountAuth.started, isFalse);
      expect(await productionDeleteRpc(), 'unavailable');
      await productionSignOut();
      productionStopRefresh();
    },
  );

  test('a null active subject leaves the phase unchanged', () async {
    final ProfileStore store = openStore();
    final AccountController account = accountFor(store);
    account.phase = AccountPhase.signedIn;
    await account.openExportPreview();
    expect(account.phase, AccountPhase.signedIn);
    await account.openDeletePreview();
    expect(account.phase, AccountPhase.signedIn);
  });

  test(
    'excludeFromBackup failure yields notSaved and confirmInFlight is false',
    () async {
      final ProfileStore store = openStore(
        excludeFromBackup: (String path) async {
          if (File('$path${Platform.pathSeparator}export.json').existsSync()) {
            throw StateError('exclude failed');
          }
        },
      );
      final String subjectId = await store.createProfile();
      final AccountController account = accountFor(store);
      account.accountRouteOpen = true;
      var sawInFlight = false;
      store.onExportFileCreated = () async {
        sawInFlight = account.confirmInFlight;
      };
      await account.openExportPreview();
      await account.confirmExport();
      expect(sawInFlight, isTrue);
      expect(account.confirmInFlight, isFalse);
      expect(account.exportResult, ExportResult.notSaved);
      expect(exportFile(subjectId).existsSync(), isFalse);
    },
  );

  test('a saved export keeps the file until the route closes', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final AccountController account = accountFor(store);
    account.accountRouteOpen = true;
    await account.openExportPreview();
    await account.confirmExport();
    expect(account.exportResult, ExportResult.saved);
    expect(exportFile(subjectId).existsSync(), isTrue);
    account.closeAccountRoute();
    expect(account.exportResult, isNull);
    expect(exportFile(subjectId).existsSync(), isFalse);
  });

  test('a generation mismatch before the write saves nothing', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final _ScriptedUnlock unlock = _ScriptedUnlock();
    final AccountController account = accountFor(store, phoneUnlock: unlock);
    account.accountRouteOpen = true;
    await account.openExportPreview();
    final Completer<PhoneUnlockDecision> gate =
        Completer<PhoneUnlockDecision>();
    unlock.authGate = gate;
    final Future<void> pending = account.confirmExport();
    await Future<void>.delayed(Duration.zero);
    account.cancelBind();
    gate.complete(PhoneUnlockDecision.confirmed);
    await pending;
    expect(exportFile(subjectId).existsSync(), isFalse);
    expect(account.exportResult, isNull);
  });

  test('a generation mismatch after writeExport deletes the file', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final AccountController account = accountFor(store);
    account.accountRouteOpen = true;
    await account.openExportPreview();
    store.onExportFileCreated = () async {
      account.cancelBind();
    };
    await account.confirmExport();
    expect(exportFile(subjectId).existsSync(), isFalse);
    expect(account.exportResult, isNot(ExportResult.saved));
  });

  test('closeAccountRoute during the write deletes the file and skips exportResult', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final AccountController account = accountFor(store);
    account.phase = AccountPhase.signedOut;
    account.accountRouteOpen = true;
    await account.openExportPreview();
    store.onExportFileCreated = () async {
      account.closeAccountRoute();
    };
    await account.confirmExport();
    expect(exportFile(subjectId).existsSync(), isFalse);
    expect(account.exportResult, isNull);
    expect(account.phase, isNot(AccountPhase.exportResult));
    expect(account.confirmInFlight, isFalse);
  });

  test(
    'a thrown RPC and an unchanged RPC stay here and keep the keys',
    () async {
      final ProfileStore store = openStore();
      final String subjectId = await store.createProfile();
      await store.keys.write(AccountController.actorItem(_actor), subjectId);
      await store.keys.write(supabasePersistSessionKey, 'session-token');
      Future<AccountController> run(DeleteRpc deleteRpc) async {
        final AccountController account = accountFor(
          store,
          sessionReady: () => true,
          deleteRpc: deleteRpc,
        );
        account.actorId = _actor;
        account.phase = AccountPhase.signedIn;
        account.accountRouteOpen = true;
        await account.openDeletePreview();
        await account.confirmDelete();
        return account;
      }

      final AccountController thrown = await run(() async {
        throw StateError('rpc');
      });
      expect(thrown.deleteResult, DeleteResult.stillHere);
      expect(
        Directory(
          '${temp.path}${Platform.pathSeparator}profiles'
          '${Platform.pathSeparator}$subjectId',
        ).existsSync(),
        isTrue,
      );
      expect(
        await store.keys.read(AccountController.actorItem(_actor)),
        subjectId,
      );
      expect(await store.keys.read(supabasePersistSessionKey), 'session-token');

      final AccountController unchanged = await run(() async => 'unchanged');
      expect(unchanged.deleteResult, DeleteResult.stillHere);
      expect(
        await store.keys.read(AccountController.actorItem(_actor)),
        subjectId,
      );
      expect(await store.keys.read(supabasePersistSessionKey), 'session-token');
    },
  );

  test(
    'a closed route does not enter deleteResult or delete the directory',
    () async {
      final ProfileStore store = openStore();
      final String subjectId = await store.createProfile();
      final AccountController account = accountFor(store);
      account.accountRouteOpen = true;
      await account.openDeletePreview();
      account.accountRouteOpen = false;
      await account.confirmDelete();
      expect(account.deleteResult, isNull);
      expect(account.phase, isNot(AccountPhase.deleteResult));
      expect(
        Directory(
          '${temp.path}${Platform.pathSeparator}profiles'
          '${Platform.pathSeparator}$subjectId',
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('a sessionless cancel does not remove the directory', () async {
    final _HoldExportStore store = _HoldExportStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 8),
      random: Random(4),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    final String subjectId = await store.createProfile();
    final AccountController account = accountFor(store);
    account.accountRouteOpen = true;
    await account.openDeletePreview();
    store.hold = Completer<void>();
    final Future<void> pending = account.confirmDelete();
    for (var i = 0; i < 40 && !account.confirmInFlight; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(account.confirmInFlight, isTrue);
    account.cancelDelete();
    store.hold!.complete();
    await pending;
    expect(store.removals, 0);
    expect(account.deleteResult, DeleteResult.cancelled);
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles'
        '${Platform.pathSeparator}$subjectId',
      ).existsSync(),
      isTrue,
    );
    expect(account.confirmInFlight, isFalse);
  });

  test('a generation change before the RPC deletes nothing', () async {
    final _HoldExportStore store = _HoldExportStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 8),
      random: Random(4),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    final String subjectId = await store.createProfile();
    var rpcCalls = 0;
    final AccountController account = accountFor(
      store,
      sessionReady: () => true,
      deleteRpc: () async {
        rpcCalls += 1;
        return 'deleted';
      },
    );
    account.actorId = _actor;
    account.accountRouteOpen = true;
    await account.openDeletePreview();
    store.hold = Completer<void>();
    final Future<void> pending = account.confirmDelete();
    for (var i = 0; i < 40 && !account.confirmInFlight; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(account.confirmInFlight, isTrue);
    account.cancelBind();
    store.hold!.complete();
    await pending;
    expect(rpcCalls, 0);
    expect(store.removals, 0);
    expect(account.deleteResult, isNull);
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles'
        '${Platform.pathSeparator}$subjectId',
      ).existsSync(),
      isTrue,
    );
  });

  test('a generation change before local removal deletes nothing', () async {
    final _HoldExportStore store = _HoldExportStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 8),
      random: Random(4),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    final String subjectId = await store.createProfile();
    final AccountController account = accountFor(store);
    account.accountRouteOpen = true;
    await account.openDeletePreview();
    store.hold = Completer<void>();
    final Future<void> pending = account.confirmDelete();
    for (var i = 0; i < 40 && !account.confirmInFlight; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(account.confirmInFlight, isTrue);
    account.cancelBind();
    store.hold!.complete();
    await pending;
    expect(store.removals, 0);
    expect(account.deleteResult, isNull);
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles'
        '${Platform.pathSeparator}$subjectId',
      ).existsSync(),
      isTrue,
    );
  });

  test('a cancel while deletion is queued deletes nothing', () async {
    final _HoldActorRead keys = _HoldActorRead(MemoryProfileKeyStore());
    final ProfileStore store = openStore(keys: keys);
    final String subjectId = await store.createProfile();
    await keys.write(AccountController.actorItem(_actor), subjectId);
    var rpcCalls = 0;
    final AccountController account = accountFor(
      store,
      sessionReady: () => true,
      deleteRpc: () async {
        rpcCalls += 1;
        return 'deleted';
      },
    );
    account.actorId = _actor;
    account.accountRouteOpen = true;
    keys.hold = Completer<void>();
    final Future<void> binding = account.confirmBind();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await account.openDeletePreview();
    final Future<void> pending = account.confirmDelete();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(account.confirmInFlight, isTrue);
    account.cancelDelete();
    keys.hold!.complete();
    await binding;
    await pending;
    expect(rpcCalls, 0);
    expect(account.deleteResult, DeleteResult.cancelled);
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles'
        '${Platform.pathSeparator}$subjectId',
      ).existsSync(),
      isTrue,
    );
  });

  test('a cancel while export is queued writes nothing', () async {
    final _HoldActorRead keys = _HoldActorRead(MemoryProfileKeyStore());
    final ProfileStore store = openStore(keys: keys);
    final String subjectId = await store.createProfile();
    await keys.write(AccountController.actorItem(_actor), subjectId);
    final AccountController account = accountFor(store);
    account.actorId = _actor;
    account.accountRouteOpen = true;
    keys.hold = Completer<void>();
    final Future<void> binding = account.confirmBind();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await account.openExportPreview();
    final Future<void> pending = account.confirmExport();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(account.confirmInFlight, isTrue);
    account.cancelExport();
    keys.hold!.complete();
    await binding;
    await pending;
    expect(exportFile(subjectId).existsSync(), isFalse);
    expect(account.exportResult, ExportResult.cancelled);
  });

  test('a second delete confirmation does not send another RPC', () async {
    final _HoldActorRead keys = _HoldActorRead(MemoryProfileKeyStore());
    final ProfileStore store = openStore(keys: keys);
    final String subjectId = await store.createProfile();
    await keys.write(AccountController.actorItem(_actor), subjectId);
    var rpcCalls = 0;
    final AccountController account = accountFor(
      store,
      sessionReady: () => true,
      deleteRpc: () async {
        rpcCalls += 1;
        return 'unchanged';
      },
    );
    account.actorId = _actor;
    account.accountRouteOpen = true;
    keys.hold = Completer<void>();
    final Future<void> binding = account.confirmBind();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await account.openDeletePreview();
    final Future<void> first = account.confirmDelete();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(account.confirmInFlight, isTrue);
    final Future<void> second = account.confirmDelete();
    await second;
    expect(rpcCalls, 0);
    keys.hold!.complete();
    await binding;
    await first;
    expect(rpcCalls, 1);
    expect(account.deleteResult, DeleteResult.stillHere);
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles'
        '${Platform.pathSeparator}$subjectId',
      ).existsSync(),
      isTrue,
    );
  });

  test('a thrown actor key delete still removes the directory', () async {
    final _ThrowingDeletes keys = _ThrowingDeletes(MemoryProfileKeyStore());
    keys.failActor = true;
    final ProfileStore store = openStore(keys: keys);
    final String subjectId = await store.createProfile();
    var rpcCalls = 0;
    final AccountController account = accountFor(
      store,
      sessionReady: () => true,
      deleteRpc: () async {
        rpcCalls += 1;
        return 'deleted';
      },
    );
    account.actorId = _actor;
    account.accountRouteOpen = true;
    await account.openDeletePreview();
    await account.confirmDelete();
    expect(rpcCalls, 1);
    expect(account.deleteResult, isNot(DeleteResult.stillHere));
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles'
        '${Platform.pathSeparator}$subjectId',
      ).existsSync(),
      isFalse,
    );
  });

  test('a thrown session key delete still removes the directory', () async {
    final _ThrowingDeletes keys = _ThrowingDeletes(MemoryProfileKeyStore());
    keys.failSession = true;
    final ProfileStore store = openStore(keys: keys);
    final String subjectId = await store.createProfile();
    final AccountController account = accountFor(
      store,
      sessionReady: () => true,
      deleteRpc: () async => 'deleted',
    );
    account.actorId = _actor;
    account.accountRouteOpen = true;
    await account.openDeletePreview();
    await account.confirmDelete();
    expect(account.deleteResult, DeleteResult.removedWithSignIn);
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles'
        '${Platform.pathSeparator}$subjectId',
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'a null captured actor omits the sign-in sentence even with a session',
    () async {
      final ProfileStore store = openStore();
      await store.createProfile();
      final AccountController account = accountFor(
        store,
        sessionReady: () => true,
      );
      account.accountRouteOpen = true;
      await account.openDeletePreview();
      expect(account.namesSignInRemoval, isFalse);
    },
  );

  test('sign-out runs before the refresh stop and a committed delete replaces the profile', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    await store.keys.write(AccountController.actorItem(_actor), subjectId);
    await store.keys.write(supabasePersistSessionKey, 'session-token');
    final List<String> order = <String>[];
    AccountAuth.started = true;
    final AccountController account = accountFor(
      store,
      sessionReady: () => true,
      deleteRpc: () async => 'deleted',
      signOutAction: () async {
        order.add('signOut');
      },
      stopRefresh: () {
        order.add('stop');
      },
    );
    account.actorId = _actor;
    account.phase = AccountPhase.signedIn;
    account.accountRouteOpen = true;
    await account.openDeletePreview();
    expect(account.namesSignInRemoval, isTrue);
    await account.confirmDelete();
    expect(order, <String>['signOut', 'stop']);
    expect(account.deleteResult, DeleteResult.removedWithSignIn);
    expect(account.rpcCommitted, isTrue);
    expect(account.actorId, isNull);
    expect(await store.keys.read(AccountController.actorItem(_actor)), isNull);
    expect(await store.keys.read(supabasePersistSessionKey), isNull);
    expect(store.hasOpenDatabase, isTrue);
    expect(store.activeSubjectId, isNot(subjectId));
  });

  test('a thrown sign-out still stops refresh', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    await store.keys.write(AccountController.actorItem(_actor), subjectId);
    final List<String> order = <String>[];
    AccountAuth.started = true;
    final AccountController account = accountFor(
      store,
      sessionReady: () => true,
      deleteRpc: () async => 'deleted',
      signOutAction: () async {
        order.add('signOut');
        throw StateError('sign-out');
      },
      stopRefresh: () {
        order.add('stop');
      },
    );
    account.actorId = _actor;
    account.accountRouteOpen = true;
    await account.openDeletePreview();
    await account.confirmDelete();
    expect(order, <String>['signOut', 'stop']);
    expect(account.deleteResult, isNot(DeleteResult.stillHere));
  });

  test(
    'a generation mismatch after a committed RPC does not stay here',
    () async {
      final ProfileStore store = openStore();
      final String subjectId = await store.createProfile();
      late AccountController account;
      account = accountFor(
        store,
        sessionReady: () => true,
        deleteRpc: () async {
          account.cancelBind();
          return 'deleted';
        },
      );
      account.actorId = _actor;
      account.accountRouteOpen = true;
      await account.openDeletePreview();
      await account.confirmDelete();
      expect(account.deleteResult, isNot(DeleteResult.stillHere));
      expect(
        Directory(
          '${temp.path}${Platform.pathSeparator}profiles'
          '${Platform.pathSeparator}$subjectId',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'an actor without a session deletes locally and does not call the RPC',
    () async {
      final ProfileStore store = openStore();
      final String subjectId = await store.createProfile();
      await store.keys.write(AccountController.actorItem(_actor), subjectId);
      await store.keys.write(supabasePersistSessionKey, 'session-token');
      var rpcCalls = 0;
      final AccountController account = accountFor(
        store,
        deleteRpc: () async {
          rpcCalls += 1;
          return 'deleted';
        },
      );
      account.actorId = _actor;
      account.accountRouteOpen = true;
      await account.openDeletePreview();
      expect(account.namesSignInRemoval, isFalse);
      await account.confirmDelete();
      expect(rpcCalls, 0);
      expect(account.deleteResult, DeleteResult.removed);
      expect(account.actorId, isNull);
      expect(
        await store.keys.read(AccountController.actorItem(_actor)),
        isNull,
      );
      expect(await store.keys.read(supabasePersistSessionKey), isNull);
      expect(store.activeSubjectId, isNot(subjectId));
    },
  );

  test('notReplaced does not say the profile is still here', () async {
    final _FailCreateStore store = _FailCreateStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 8),
      random: Random(9),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    final String subjectId = await store.createProfile();
    final AccountController account = accountFor(store);
    account.accountRouteOpen = true;
    await account.openDeletePreview();
    store.failCreate = true;
    await account.confirmDelete();
    expect(account.deleteResult, DeleteResult.notReplaced);
    expect(account.rpcCommitted, isFalse);
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles'
        '${Platform.pathSeparator}$subjectId',
      ).existsSync(),
      isFalse,
    );
    store.failCreate = false;
    await account.retryCreateProfile();
    expect(account.deleteResult, DeleteResult.removed);
    expect(store.hasOpenDatabase, isTrue);
  });

  test(
    'directoryRemained leaves the key and Try again does not call the RPC',
    () async {
      final ProfileStore store = openStore();
      final String subjectId = await store.createProfile();
      await store.keys.write(AccountController.actorItem(_actor), subjectId);
      await store.keys.write(supabasePersistSessionKey, 'session-token');
      store.onBeforeDirectoryDelete = () async {
        throw StateError('directory locked');
      };
      var rpcCalls = 0;
      AccountAuth.started = true;
      final AccountController account = accountFor(
        store,
        sessionReady: () => true,
        deleteRpc: () async {
          rpcCalls += 1;
          return 'deleted';
        },
      );
      account.actorId = _actor;
      account.accountRouteOpen = true;
      await account.openDeletePreview();
      await account.confirmDelete();
      expect(account.deleteResult, DeleteResult.signInRemoved);
      expect(await store.keys.read(profileKeyItem(subjectId)), isNotNull);
      expect(rpcCalls, 1);
      await account.retryLocalDelete();
      expect(rpcCalls, 1);
      expect(account.rpcCommitted, isTrue);
    },
  );

  test(
    'a checkpoint failure during deletion leaves the profile and can be retried',
    () async {
      final ProfileStore store = openStore();
      final String subjectId = await store.createProfile();
      store.onBeforeCheckpoint = () async {
        throw const StorageIoException('checkpoint failed');
      };
      final AccountController account = accountFor(store);
      account.accountRouteOpen = true;
      await account.openDeletePreview();
      await account.confirmDelete();
      expect(account.deleteResult, DeleteResult.stillHere);
      expect(account.confirmInFlight, isFalse);
      expect(store.activeSubjectId, subjectId);
      expect(
        Directory(
          '${temp.path}${Platform.pathSeparator}profiles'
          '${Platform.pathSeparator}$subjectId',
        ).existsSync(),
        isTrue,
      );
      expect(await store.keys.read(profileKeyItem(subjectId)), isNotNull);

      store.onBeforeCheckpoint = null;
      await account.confirmDelete();
      expect(account.deleteResult, DeleteResult.removed);
      expect(
        Directory(
          '${temp.path}${Platform.pathSeparator}profiles'
          '${Platform.pathSeparator}$subjectId',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'a checkpoint failure after a committed RPC does not call the RPC again',
    () async {
      final ProfileStore store = openStore();
      final String subjectId = await store.createProfile();
      await store.keys.write(AccountController.actorItem(_actor), subjectId);
      await store.keys.write(supabasePersistSessionKey, 'session-token');
      store.onBeforeCheckpoint = () async {
        throw const StorageIoException('checkpoint failed');
      };
      var rpcCalls = 0;
      AccountAuth.started = true;
      final AccountController account = accountFor(
        store,
        sessionReady: () => true,
        deleteRpc: () async {
          rpcCalls += 1;
          return 'deleted';
        },
      );
      account.actorId = _actor;
      account.accountRouteOpen = true;
      await account.openDeletePreview();
      await account.confirmDelete();
      expect(account.deleteResult, DeleteResult.signInRemoved);
      expect(account.confirmInFlight, isFalse);
      expect(store.activeSubjectId, subjectId);
      expect(rpcCalls, 1);
      expect(await store.keys.read(profileKeyItem(subjectId)), isNotNull);

      store.onBeforeCheckpoint = null;
      await account.retryLocalDelete();
      expect(rpcCalls, 1);
      expect(account.deleteResult, DeleteResult.removedWithSignIn);
    },
  );

  test(
    'dismissResult restores the captured phase and clears both results',
    () async {
      final ProfileStore store = openStore();
      await store.createProfile();
      final AccountController account = accountFor(store);
      account.phase = AccountPhase.signedIn;
      account.accountRouteOpen = true;
      await account.openExportPreview();
      account.cancelExport();
      expect(account.phase, AccountPhase.exportResult);
      expect(account.exportResult, ExportResult.cancelled);
      account.dismissResult();
      expect(account.phase, AccountPhase.signedIn);
      expect(account.exportResult, isNull);
      expect(account.deleteResult, isNull);
    },
  );

  test(
    'closeAccountRoute after a cleared profile does not restore signedIn',
    () async {
      final ProfileStore store = openStore();
      await store.createProfile();
      final AccountController account = accountFor(store);
      account.actorId = _actor;
      account.phase = AccountPhase.signedIn;
      account.accountRouteOpen = true;
      await account.openDeletePreview();
      await account.confirmDelete();
      expect(account.deleteResult, DeleteResult.removed);
      account.closeAccountRoute();
      expect(account.phase, AccountPhase.signedOut);
      expect(account.deleteResult, isNull);
      expect(account.exportResult, isNull);
    },
  );

  testWidgets('direct privacy navigation opens account with an empty query', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(store.createProfile);
    final _ScriptedUnlock unlock = _ScriptedUnlock();
    final GoRouter router = buildHelpMeMoveRouter(
      initialLocation: '/focus/privacy',
      store: store,
      phoneUnlock: unlock,
    );
    addTearDown(router.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    await _until(tester, find.text('Prepare a copy on this phone'));
    expect(find.text('Delete the profile on this phone'), findsOneWidget);
    await tester.ensureVisible(find.text('Prepare a copy on this phone'));
    await tester.tap(find.text('Prepare a copy on this phone'));
    await _until(tester, find.text('Save a copy of this profile?'));
    expect(router.routeInformationProvider.value.uri.path, '/focus/account');
    expect(router.routeInformationProvider.value.uri.hasQuery, isFalse);
    router.go('/focus/privacy');
    await _until(tester, find.text('Delete the profile on this phone'));
    await tester.ensureVisible(find.text('Delete the profile on this phone'));
    await tester.tap(find.text('Delete the profile on this phone'));
    await _until(tester, find.text('Remove this profile?'));
    expect(router.routeInformationProvider.value.uri.path, '/focus/account');
    expect(router.routeInformationProvider.value.uri.hasQuery, isFalse);
    expect(
      find.text('This sign-in is removed with the profile.'),
      findsNothing,
    );
  });

  testWidgets('unlock gates hide the action buttons', (tester) async {
    final ProfileStore store = openStore();
    await tester.runAsync(store.createProfile);
    final _ScriptedUnlock unlock = _ScriptedUnlock();
    final AccountController account = accountFor(store, phoneUnlock: unlock);
    await _pumpAccount(tester, account);
    final Completer<PhoneUnlockSupport> support =
        Completer<PhoneUnlockSupport>();
    unlock.supportGate = support;
    final Future<void> opening = account.openExportPreview();
    await tester.pump();
    expect(find.text("Checking this phone's unlock."), findsOneWidget);
    expect(find.text('Prepare the file'), findsNothing);
    expect(find.text('Not now'), findsNothing);
    support.complete(PhoneUnlockSupport.unavailable);
    await opening;
    await tester.pump();
    expect(
      find.text(
        "This phone has no unlock check, so this action is unavailable.",
      ),
      findsOneWidget,
    );
    expect(find.text('Prepare the file'), findsNothing);
    expect(find.text('Remove it'), findsNothing);

    unlock.supportGate = null;
    unlock.support = PhoneUnlockSupport.ready;
    unlock.decision = PhoneUnlockDecision.canceled;
    await account.confirmExport();
    await tester.pump();
    expect(find.text('Nothing was saved or removed.'), findsOneWidget);

    unlock.decision = PhoneUnlockDecision.unfinished;
    await account.confirmExport();
    await tester.pump();
    expect(
      find.text(
        'The phone unlock check did not finish. Nothing was saved or removed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a canceled retry still shows the unlock sentence', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(store.createProfile);
    final _ScriptedUnlock unlock = _ScriptedUnlock()
      ..decision = PhoneUnlockDecision.canceled;
    final AccountController account = accountFor(store, phoneUnlock: unlock);
    account.accountRouteOpen = true;
    await account.openExportPreview();
    account.phase = AccountPhase.exportResult;
    account.exportResult = ExportResult.notSaved;
    account.unlockGate = PhoneUnlockGate.ready;
    await _pumpAccount(tester, account);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('The file was not prepared.'), findsOneWidget);
    expect(find.text('Nothing was saved or removed.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(exportFile(store.activeSubjectId!).existsSync(), isFalse);

    unlock.decision = PhoneUnlockDecision.unfinished;
    account.phase = AccountPhase.deleteResult;
    account.deleteResult = DeleteResult.stillHere;
    account.exportResult = null;
    account.unlockGate = PhoneUnlockGate.ready;
    account.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('The profile is still on this phone.'), findsOneWidget);
    expect(
      find.text(
        'The phone unlock check did not finish. Nothing was saved or removed.',
      ),
      findsOneWidget,
    );
  });

  test('a confirmed retry clears a canceled unlock sentence', () async {
    final ProfileStore store = openStore();
    final String subjectId = await store.createProfile();
    final _ScriptedUnlock unlock = _ScriptedUnlock()
      ..decision = PhoneUnlockDecision.canceled;
    final AccountController account = accountFor(store, phoneUnlock: unlock);
    account.accountRouteOpen = true;
    await account.openExportPreview();
    account.phase = AccountPhase.exportResult;
    account.exportResult = ExportResult.notSaved;
    await account.confirmExport();
    expect(account.unlockGate, PhoneUnlockGate.canceled);
    expect(exportFile(subjectId).existsSync(), isFalse);

    unlock.decision = PhoneUnlockDecision.confirmed;
    await account.confirmExport();
    expect(account.exportResult, ExportResult.saved);
    expect(account.unlockGate, PhoneUnlockGate.ready);
    expect(exportFile(subjectId).existsSync(), isTrue);

    unlock.decision = PhoneUnlockDecision.canceled;
    account.phase = AccountPhase.deleteResult;
    account.deleteResult = DeleteResult.stillHere;
    await account.confirmDelete();
    expect(account.unlockGate, PhoneUnlockGate.canceled);
    expect(account.deleteResult, DeleteResult.stillHere);

    unlock.decision = PhoneUnlockDecision.confirmed;
    await account.confirmDelete();
    expect(account.unlockGate, PhoneUnlockGate.ready);
    expect(account.deleteResult, DeleteResult.removed);
  });

  test('a second recovery retry does not create another profile', () async {
    final _HoldCreateStore store = _HoldCreateStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 8),
      random: Random(7),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await store.createProfile();
    final AccountController account = accountFor(store);
    account.accountRouteOpen = true;
    await account.openDeletePreview();
    account.phase = AccountPhase.deleteResult;
    account.deleteResult = DeleteResult.notReplaced;
    store.hold = Completer<void>();
    final Future<void> first = account.retryCreateProfile();
    await Future<void>.delayed(Duration.zero);
    expect(account.confirmInFlight, isTrue);
    final Future<void> second = account.retryCreateProfile();
    store.hold!.complete();
    await first;
    await second;
    expect(store.retryCreates, 1);
    expect(account.deleteResult, DeleteResult.removed);
    expect(account.confirmInFlight, isFalse);
  });

  testWidgets('confirmInFlight and rpcDispatched hide the action buttons', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(store.createProfile);
    final AccountController account = accountFor(store);
    account.accountRouteOpen = true;
    await account.openExportPreview();
    account.confirmInFlight = true;
    await _pumpAccount(tester, account);
    expect(find.text('Preparing the file on this phone.'), findsOneWidget);
    expect(find.text('Prepare the file'), findsNothing);

    account.confirmInFlight = false;
    await account.openDeletePreview();
    account.confirmInFlight = true;
    account.rpcDispatched = true;
    account.notifyListeners();
    await tester.pump();
    expect(find.text('Removing this profile.'), findsOneWidget);
    expect(find.text('Remove it'), findsNothing);
    expect(find.text('Not now'), findsNothing);

    account.phase = AccountPhase.deleteResult;
    account.deleteResult = DeleteResult.notReplaced;
    account.notifyListeners();
    await tester.pump();
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Removing this profile.'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('results use the spec sentences and Back', (tester) async {
    final ProfileStore store = openStore();
    await tester.runAsync(store.createProfile);
    final AccountController account = accountFor(
      store,
      sessionReady: () => true,
    );
    account.accountRouteOpen = true;
    await account.openExportPreview();
    account.phase = AccountPhase.exportResult;
    account.exportResult = ExportResult.saved;
    await _pumpAccount(tester, account);
    expect(
      find.text(
        'The file stays on this phone until you leave this screen. The copy is not encrypted. If the app closes first, the next launch removes it. This build does not open it or send it.',
      ),
      findsOneWidget,
    );
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);

    account.exportResult = ExportResult.notSaved;
    account.notifyListeners();
    await tester.pump();
    expect(find.text('The file was not prepared.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    account.exportResult = ExportResult.cancelled;
    account.notifyListeners();
    await tester.pump();
    expect(find.text('No file was prepared.'), findsOneWidget);

    account.actorId = _actor;
    await account.openDeletePreview();
    await tester.pump();
    expect(
      find.text('This sign-in is removed with the profile.'),
      findsOneWidget,
    );
    account.phase = AccountPhase.deleteResult;
    account.deleteResult = DeleteResult.stillHere;
    account.notifyListeners();
    await tester.pump();
    expect(find.text('The profile is still on this phone.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    account.deleteResult = DeleteResult.signInRemoved;
    account.notifyListeners();
    await tester.pump();
    expect(
      find.text('The sign-in was removed. The profile is still on this phone.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);

    account.deleteResult = DeleteResult.removed;
    account.notifyListeners();
    await tester.pump();
    expect(
      find.text('This profile was removed from this phone.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsNothing);

    account.deleteResult = DeleteResult.removedWithSignIn;
    account.notifyListeners();
    await tester.pump();
    expect(
      find.text(
        'This profile was removed from this phone. This sign-in was removed with it.',
      ),
      findsOneWidget,
    );

    account.deleteResult = DeleteResult.notReplaced;
    account.notifyListeners();
    await tester.pump();
    expect(
      find.text(
        'The profile was removed from this phone. A new profile was not opened.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a committed notReplaced sentence names the sign-in', (
    tester,
  ) async {
    final _ScriptedRemovalStore store = _ScriptedRemovalStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 8),
      random: Random(12),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await tester.runAsync(store.createProfile);
    final AccountController account = accountFor(
      store,
      sessionReady: () => true,
      deleteRpc: () async => 'deleted',
    );
    account.actorId = _actor;
    account.accountRouteOpen = true;
    store.nextRemoval = LocalRemoval.notReplaced;
    await account.openDeletePreview();
    await account.confirmDelete();
    await _pumpAccount(tester, account);
    expect(
      find.text(
        'The profile was removed from this phone. This sign-in was removed with it. A new profile was not opened.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(account.rpcCommitted, isTrue);
  });

  testWidgets('leaving the account route disposes without throwing', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    final String? subjectId = await tester.runAsync(store.createProfile);
    await tester.runAsync(store.writeExport);
    final AccountController account = accountFor(store);
    var notifications = 0;
    final GoRouter router = GoRouter(
      initialLocation: '/focus/account',
      routes: <RouteBase>[
        GoRoute(
          path: '/focus/account',
          builder: (BuildContext context, GoRouterState state) {
            return AccountScreen(controller: account);
          },
        ),
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) {
            return const Text('home-marker');
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    await tester.pump();
    expect(account.accountRouteOpen, isTrue);
    account.addListener(() {
      notifications += 1;
    });
    router.go('/');
    await tester.pump();
    await tester.pump();
    expect(find.text('home-marker'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(notifications, 0);
    expect(account.accountRouteOpen, isFalse);
    expect(exportFile(subjectId!).existsSync(), isFalse);
  });

  testWidgets(
    'non-deleting Back opens privacy and a deleting Back stays signed out',
    (tester) async {
      final ProfileStore store = openStore();
      await tester.runAsync(store.createProfile);
      final AccountController account = accountFor(store);
      account.accountRouteOpen = true;
      await account.openExportPreview();
      account.cancelExport();
      final GoRouter router = GoRouter(
        initialLocation: '/focus/account',
        routes: <RouteBase>[
          GoRoute(
            path: '/focus/account',
            builder: (BuildContext context, GoRouterState state) {
              return AccountScreen(controller: account);
            },
          ),
          GoRoute(
            path: '/focus/privacy',
            builder: (BuildContext context, GoRouterState state) {
              return const Text('privacy-marker');
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      );
      await tester.pump();
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump();
      expect(find.text('privacy-marker'), findsOneWidget);
      expect(account.phase, AccountPhase.signedOut);

      account.phase = AccountPhase.deleteResult;
      account.deleteResult = DeleteResult.removed;
      account.accountRouteOpen = true;
      router.go('/focus/account');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('privacy-marker'), findsNothing);
      expect(
        find.text(
          'An account is optional. Workouts on this device stay on this device.',
        ),
        findsOneWidget,
      );
      expect(account.phase, AccountPhase.signedOut);
      expect(account.deleteResult, isNull);
    },
  );
}

Future<void> _pumpAccount(
  WidgetTester tester,
  AccountController account,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AccountScreen(controller: account),
    ),
  );
  await tester.pump();
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
  }
  fail('missing $finder');
}

class _ScriptedUnlock implements PhoneUnlock {
  PhoneUnlockSupport support = PhoneUnlockSupport.ready;
  PhoneUnlockDecision decision = PhoneUnlockDecision.confirmed;
  Completer<PhoneUnlockSupport>? supportGate;
  Completer<PhoneUnlockDecision>? authGate;

  @override
  Future<PhoneUnlockSupport> isDeviceSupported() {
    final Completer<PhoneUnlockSupport>? gate = supportGate;
    if (gate != null) {
      return gate.future;
    }
    return Future<PhoneUnlockSupport>.value(support);
  }

  @override
  Future<PhoneUnlockDecision> authenticate() {
    final Completer<PhoneUnlockDecision>? gate = authGate;
    if (gate != null) {
      return gate.future;
    }
    return Future<PhoneUnlockDecision>.value(decision);
  }
}

class _HoldExportStore extends ProfileStore {
  _HoldExportStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  Completer<void>? hold;
  int removals = 0;

  @override
  Future<void> deleteExport([String? subjectId]) async {
    final Completer<void>? gate = hold;
    if (gate != null) {
      await gate.future;
    }
    await super.deleteExport(subjectId);
  }

  @override
  Future<LocalRemoval> removeSubjectDirectoryFirst(String subjectId) {
    removals += 1;
    return super.removeSubjectDirectoryFirst(subjectId);
  }
}

class _ScriptedRemovalStore extends ProfileStore {
  _ScriptedRemovalStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  LocalRemoval nextRemoval = LocalRemoval.replaced;

  @override
  Future<LocalRemoval> removeSubjectDirectoryFirst(String subjectId) async {
    return nextRemoval;
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

class _HoldCreateStore extends ProfileStore {
  _HoldCreateStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  Completer<void>? hold;
  int retryCreates = 0;

  @override
  Future<String> createProfile() async {
    final Completer<void>? gate = hold;
    if (gate != null) {
      retryCreates += 1;
      await gate.future;
    }
    return super.createProfile();
  }
}

class _HoldActorRead implements ProfileKeyStore {
  _HoldActorRead(this.inner);

  final MemoryProfileKeyStore inner;
  Completer<void>? hold;

  @override
  Future<String?> read(String item) async {
    final Completer<void>? gate = hold;
    if (gate != null && item.startsWith('account-actor.')) {
      await gate.future;
    }
    return inner.read(item);
  }

  @override
  Future<void> write(String item, String value) => inner.write(item, value);

  @override
  Future<void> delete(String item) => inner.delete(item);
}

class _ThrowingDeletes implements ProfileKeyStore {
  _ThrowingDeletes(this.inner);

  final MemoryProfileKeyStore inner;
  bool failActor = false;
  bool failSession = false;

  @override
  Future<String?> read(String item) => inner.read(item);

  @override
  Future<void> write(String item, String value) => inner.write(item, value);

  @override
  Future<void> delete(String item) async {
    if (failActor && item.startsWith('account-actor.')) {
      throw StateError('actor key');
    }
    if (failSession && item == supabasePersistSessionKey) {
      throw StateError('session key');
    }
    await inner.delete(item);
  }
}
