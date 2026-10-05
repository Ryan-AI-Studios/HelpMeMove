import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/account/account_controller.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _actorA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const String _actorB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-account');
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
    Future<void> Function(String path)? excludeFromBackup,
  }) {
    final ProfileStore store = ProfileStore(
      keys: keys ?? MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 5),
      random: Random(7),
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

  test('cancel writes nothing and confirm binds the open profile', () async {
    final ProfileStore store = openStore();
    final AccountController account = AccountController(store: store);
    final String subject = await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    account.cancelBind();
    expect(await store.keys.read(AccountController.actorItem(_actorA)), isNull);
    expect(account.phase, AccountPhase.signedOut);

    account.beginBind();
    await account.confirmBind();
    expect(
      await store.keys.read(AccountController.actorItem(_actorA)),
      subject,
    );
    expect(account.phase, AccountPhase.signedIn);
    expect(account.cloudAccess, isTrue);
    expect(store.activeSubjectId, subject);
  });

  test(
    'an actor bound to another subject switches and does not merge',
    () async {
      final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
      final ProfileStore store = openStore(keys: keys);
      final AccountController account = AccountController(store: store);
      final String first = await store.createProfile();
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      final String second = await store.createProfile();
      expect(store.activeSubjectId, second);

      var calls = 0;
      final int epoch = account.epoch;
      final AccountSubscription subscription = account.listen(() {
        calls += 1;
      });
      keys.holdProfileKey = Completer<void>();
      final Future<void> switching = account.presentActor(_actorA);
      await pumpEventQueue();
      expect(account.phase, AccountPhase.switching);
      expect(subscription.cancelled, isTrue);
      expect(calls, 0);
      var late = 0;
      account.completeLate(epoch, () {
        late += 1;
      });
      expect(late, 0);
      keys.holdProfileKey!.complete();
      await switching;

      expect(store.activeSubjectId, first);
      expect(profileDirectory(second).existsSync(), isTrue);
      expect(await store.keys.read(profileKeyItem(second)), isNotNull);
      expect(account.phase, AccountPhase.signedIn);
      expect(
        await store.keys.read(AccountController.actorItem(_actorA)),
        first,
      );
    },
  );

  test('a second actor does not open the other subject', () async {
    final ProfileStore store = openStore();
    final AccountController account = AccountController(store: store);
    final String first = await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    final String second = await store.createProfile();
    await account.presentActor(_actorB);
    expect(store.activeSubjectId, second);
    expect(await store.keys.read(AccountController.actorItem(_actorB)), isNull);
    expect(await store.keys.read(AccountController.actorItem(_actorA)), first);
    expect(account.phase, AccountPhase.signedOut);
  });

  test(
    'keep locked leaves the profile and reopens it for the same actor',
    () async {
      final ProfileStore store = openStore();
      final AccountController account = AccountController(store: store);
      final String first = await store.createProfile();
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      await store.keys.write(supabasePersistSessionKey, 'session-token');

      final int epoch = account.epoch;
      final AccountSubscription subscription = account.listen(() {});
      await account.keepLocked();
      expect(subscription.cancelled, isTrue);
      expect(store.activeSubjectId, isNull);
      expect(await store.keys.read(activeProfileItem), isNull);
      expect(await store.keys.read(profileKeyItem(first)), isNotNull);
      expect(
        await store.keys.read(AccountController.actorItem(_actorA)),
        first,
      );
      expect(await store.keys.read(supabasePersistSessionKey), isNull);
      expect(profileDirectory(first).existsSync(), isTrue);
      expect(account.cloudAccess, isFalse);
      var late = 0;
      account.completeLate(epoch, () {
        late += 1;
      });
      expect(late, 0);

      final String next = await store.createProfile();
      expect(next, isNot(first));
      await account.presentActor(_actorA);
      expect(store.activeSubjectId, first);
      expect(profileDirectory(next).existsSync(), isTrue);
      expect(account.phase, AccountPhase.signedIn);
    },
  );

  test(
    'remove local deletes only that subject and creates a new profile',
    () async {
      final ProfileStore store = openStore();
      final AccountController account = AccountController(store: store);
      final String first = await store.createProfile();
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      final String second = await store.createProfile();
      await store.switchTo(first);
      await store.keys.write(supabasePersistSessionKey, 'session-token');
      account.actorId = _actorA;

      final AccountSubscription subscription = account.listen(() {});
      await account.removeLocal();
      expect(subscription.cancelled, isTrue);
      expect(profileDirectory(first).existsSync(), isFalse);
      expect(await store.keys.read(profileKeyItem(first)), isNull);
      expect(
        await store.keys.read(AccountController.actorItem(_actorA)),
        isNull,
      );
      expect(await store.keys.read(supabasePersistSessionKey), isNull);
      expect(profileDirectory(second).existsSync(), isTrue);
      expect(await store.keys.read(profileKeyItem(second)), isNotNull);
      expect(store.activeSubjectId, isNot(first));
      expect(store.activeSubjectId, isNot(second));
      expect(account.phase, AccountPhase.signedOut);
    },
  );

  test(
    'expired sign-in keeps the profile and access removal clears the map',
    () async {
      final ProfileStore store = openStore();
      final AccountController account = AccountController(store: store);
      final String subject = await store.createProfile();
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      await store.keys.write(supabasePersistSessionKey, 'session-token');

      await account.expire();
      expect(store.activeSubjectId, subject);
      expect(account.cloudAccess, isFalse);
      expect(account.phase, AccountPhase.expired);
      expect(
        await store.keys.read(AccountController.actorItem(_actorA)),
        subject,
      );
      expect(await store.keys.read(supabasePersistSessionKey), isNull);
      expect(await store.keys.read(profileKeyItem(subject)), isNotNull);

      await store.keys.write(AccountController.actorItem(_actorA), subject);
      account.actorId = _actorA;
      await account.removeAccess();
      expect(store.activeSubjectId, subject);
      expect(
        await store.keys.read(AccountController.actorItem(_actorA)),
        isNull,
      );
      expect(account.phase, AccountPhase.accessRemoved);
      expect(profileDirectory(subject).existsSync(), isTrue);
    },
  );

  test(
    'reauthentication runs only when confirm keeps the same actor',
    () async {
      final ProfileStore store = openStore();
      final AccountController account = AccountController(store: store);
      await store.createProfile();
      account.actorId = _actorA;
      account.phase = AccountPhase.signedIn;
      var ran = false;
      account.requestReauth(() {
        ran = true;
      });
      account.cancelReauth();
      expect(ran, isFalse);
      expect(account.phase, AccountPhase.signedIn);

      account.requestReauth(() {
        ran = true;
      });
      account.actorId = _actorB;
      account.confirmReauth();
      expect(ran, isFalse);

      account.actorId = _actorA;
      account.requestReauth(() {
        ran = true;
      });
      account.confirmReauth();
      expect(ran, isTrue);
      expect(account.phase, AccountPhase.signedIn);
    },
  );

  test('a newer actor presentation wins over an older one', () async {
    final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
    final ProfileStore store = openStore(keys: keys);
    final AccountController account = AccountController(store: store);
    final String first = await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    final String second = await store.createProfile();
    await account.presentActor(_actorB);
    account.beginBind();
    await account.confirmBind();
    final String third = await store.createProfile();

    keys.holdActor = Completer<void>();
    final Future<void> older = account.presentActor(_actorA);
    final Future<void> newer = account.presentActor(_actorB);
    await pumpEventQueue();
    keys.holdActor!.complete();
    await older;
    await newer;

    expect(account.actorId, _actorB);
    expect(store.activeSubjectId, second);
    expect(account.phase, AccountPhase.signedIn);
    expect(account.cloudAccess, isTrue);
    expect(await store.keys.read(AccountController.actorItem(_actorA)), first);
    expect(await store.keys.read(AccountController.actorItem(_actorB)), second);
    expect(profileDirectory(third).existsSync(), isTrue);
  });

  test('cancel during confirm writes nothing', () async {
    final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
    final ProfileStore store = openStore(keys: keys);
    final AccountController account = AccountController(store: store);
    await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    keys.holdActor = Completer<void>();
    final Future<void> confirming = account.confirmBind();
    await pumpEventQueue();
    account.cancelBind();
    keys.holdActor!.complete();
    await confirming;

    expect(await store.keys.read(AccountController.actorItem(_actorA)), isNull);
    expect(account.phase, AccountPhase.signedOut);
    expect(account.cloudAccess, isFalse);
  });

  test('a failed switch clears that actor mapping only', () async {
    final ProfileStore store = openStore();
    final AccountController account = AccountController(store: store);
    final String first = await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    final String second = await store.createProfile();
    await store.keys.delete(profileKeyItem(first));

    await account.presentActor(_actorA);

    expect(account.phase, AccountPhase.accessRemoved);
    expect(account.actorId, isNull);
    expect(account.cloudAccess, isFalse);
    expect(await store.keys.read(AccountController.actorItem(_actorA)), isNull);
    expect(store.activeSubjectId, second);
    expect(profileDirectory(second).existsSync(), isTrue);
    expect(await store.keys.read(profileKeyItem(second)), isNotNull);
    expect(profileDirectory(first).existsSync(), isTrue);
  });

  test(
    'a superseded switch keeps the open profile for an unbound actor',
    () async {
      final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
      final ProfileStore store = openStore(keys: keys);
      final AccountController account = AccountController(store: store);
      final String retained = await store.createProfile();
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      final String open = await store.createProfile();

      keys.holdProfileKey = Completer<void>();
      final Future<void> older = account.presentActor(_actorA);
      await pumpEventQueue();
      expect(account.phase, AccountPhase.switching);
      expect(store.activeSubjectId, open);

      final Future<void> newer = account.presentActor(_actorB);
      keys.holdProfileKey!.complete();
      await older;
      await newer;

      expect(store.activeSubjectId, open);
      expect(await store.keys.read(activeProfileItem), open);
      expect(account.actorId, _actorB);
      expect(account.phase, AccountPhase.signedOut);
      expect(account.cloudAccess, isFalse);
      expect(
        await store.keys.read(AccountController.actorItem(_actorA)),
        retained,
      );
      expect(
        await store.keys.read(AccountController.actorItem(_actorB)),
        isNull,
      );
      expect(profileDirectory(retained).existsSync(), isTrue);
      expect(await store.keys.read(profileKeyItem(retained)), isNotNull);

      account.beginBind();
      await account.confirmBind();
      expect(store.activeSubjectId, open);
      expect(await store.keys.read(AccountController.actorItem(_actorB)), open);
      expect(
        await store.keys.read(AccountController.actorItem(_actorA)),
        retained,
      );
    },
  );

  test(
    'remove during a delayed presentation deletes the open actor only',
    () async {
      final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
      final ProfileStore store = openStore(keys: keys);
      final AccountController account = AccountController(store: store);
      final String retained = await store.createProfile();
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      final String open = await store.createProfile();
      await account.presentActor(_actorB);
      account.beginBind();
      await account.confirmBind();
      account.requestSignOut();
      expect(account.phase, AccountPhase.signOutChoice);

      keys.holdActor = Completer<void>();
      final Future<void> presenting = account.presentActor(_actorA);
      await pumpEventQueue();
      expect(account.actorId, _actorB);
      expect(account.phase, AccountPhase.signOutChoice);
      expect(store.activeSubjectId, open);

      final Future<void> removing = account.removeLocal();
      keys.holdActor!.complete();
      await presenting;
      await removing;

      expect(
        await store.keys.read(AccountController.actorItem(_actorB)),
        isNull,
      );
      expect(await store.keys.read(profileKeyItem(open)), isNull);
      expect(profileDirectory(open).existsSync(), isFalse);
      expect(
        await store.keys.read(AccountController.actorItem(_actorA)),
        retained,
      );
      expect(await store.keys.read(profileKeyItem(retained)), isNotNull);
      expect(profileDirectory(retained).existsSync(), isTrue);
      expect(store.activeSubjectId, isNot(open));
      expect(store.activeSubjectId, isNot(retained));
      expect(account.actorId, isNull);
      expect(account.phase, AccountPhase.signedOut);
    },
  );

  test('keep locked deletes the session when a newer actor arrives', () async {
    final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
    final ProfileStore store = openStore(keys: keys);
    final AccountController account = AccountController(store: store);
    final String subject = await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    await store.keys.write(supabasePersistSessionKey, 'session-token');
    final int epoch = account.epoch;
    final AccountSubscription subscription = account.listen(() {});

    keys.holdActiveDelete = Completer<void>();
    keys.enteredActiveDelete = Completer<void>();
    final Future<void> keeping = account.keepLocked();
    await keys.enteredActiveDelete!.future.timeout(const Duration(seconds: 5));
    expect(store.activeSubjectId, isNull);
    expect(subscription.cancelled, isTrue);

    final Future<void> newer = account.presentActor(_actorB);
    keys.holdActiveDelete!.complete();
    await keeping;
    await newer;

    expect(await store.keys.read(activeProfileItem), isNull);
    expect(await store.keys.read(supabasePersistSessionKey), isNull);
    expect(await store.keys.read(profileKeyItem(subject)), isNotNull);
    expect(
      await store.keys.read(AccountController.actorItem(_actorA)),
      subject,
    );
    expect(profileDirectory(subject).existsSync(), isTrue);
    var late = 0;
    account.completeLate(epoch, () {
      late += 1;
    });
    expect(late, 0);
    expect(account.actorId, _actorB);
    expect(account.phase, AccountPhase.signedOut);
    expect(account.cloudAccess, isFalse);
    expect(store.activeSubjectId, isNull);
  });

  test(
    'keep locked clears the session when a newer actor is already queued',
    () async {
      final ProfileStore store = openStore();
      final AccountController account = AccountController(store: store);
      final String subject = await store.createProfile();
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      await store.keys.write(supabasePersistSessionKey, 'session-token');

      final Future<void> keeping = account.keepLocked();
      final Future<void> newer = account.presentActor(_actorB);
      await keeping;
      await newer;

      expect(await store.keys.read(supabasePersistSessionKey), isNull);
      expect(await store.keys.read(activeProfileItem), isNull);
      expect(store.activeSubjectId, isNull);
      expect(await store.keys.read(profileKeyItem(subject)), isNotNull);
      expect(profileDirectory(subject).existsSync(), isTrue);
      expect(
        await store.keys.read(AccountController.actorItem(_actorA)),
        subject,
      );
      expect(account.actorId, _actorB);
      expect(account.phase, AccountPhase.signedOut);
      expect(account.cloudAccess, isFalse);
    },
  );

  test(
    'remove local still deletes the subject when keep locked is queued ahead',
    () async {
      final ProfileStore store = openStore();
      final AccountController account = AccountController(store: store);
      final String subject = await store.createProfile();
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      await store.keys.write(supabasePersistSessionKey, 'session-token');

      final Future<void> keeping = account.keepLocked();
      final Future<void> removing = account.removeLocal();
      await keeping;
      await removing;

      expect(
        await store.keys.read(AccountController.actorItem(_actorA)),
        isNull,
      );
      expect(await store.keys.read(profileKeyItem(subject)), isNull);
      expect(profileDirectory(subject).existsSync(), isFalse);
      expect(await store.keys.read(supabasePersistSessionKey), isNull);
      expect(store.activeSubjectId, isNotNull);
      expect(store.activeSubjectId, isNot(subject));
      expect(account.phase, AccountPhase.signedOut);
      expect(account.actorId, isNull);
    },
  );

  test(
    'expire does not replace a cancel that arrived during the session delete',
    () async {
      final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
      final ProfileStore store = openStore(keys: keys);
      final AccountController account = AccountController(store: store);
      await store.createProfile();
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      await store.keys.write(supabasePersistSessionKey, 'session-token');
      keys.holdSessionDelete = Completer<void>();
      keys.enteredSessionDelete = Completer<void>();

      final Future<void> expiring = account.expire();
      await keys.enteredSessionDelete!.future.timeout(
        const Duration(seconds: 5),
      );
      account.cancelBind();
      keys.holdSessionDelete!.complete();
      await expiring;

      expect(await store.keys.read(supabasePersistSessionKey), isNull);
      expect(account.phase, AccountPhase.signedOut);
    },
  );

  test('access removal does not replace a cancel that arrived during the mapping delete', () async {
    final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
    final ProfileStore store = openStore(keys: keys);
    final AccountController account = AccountController(store: store);
    await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    keys.holdActorDelete = Completer<void>();
    keys.enteredActorDelete = Completer<void>();

    final Future<void> removing = account.removeAccess();
    await keys.enteredActorDelete!.future.timeout(const Duration(seconds: 5));
    account.cancelBind();
    keys.holdActorDelete!.complete();
    await removing;

    expect(await store.keys.read(AccountController.actorItem(_actorA)), isNull);
    expect(account.phase, AccountPhase.signedOut);
  });

  test('a failed active-pointer write restores the previous profile', () async {
    final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
    final ProfileStore store = openStore(keys: keys);
    final AccountController account = AccountController(store: store);
    final String retained = await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    final String open = await store.createProfile();
    keys.failActiveWrites = 1;
    keys.holdActorDelete = Completer<void>();
    keys.enteredActorDelete = Completer<void>();

    final Future<void> failing = account.presentActor(_actorA);
    await keys.enteredActorDelete!.future.timeout(const Duration(seconds: 5));
    expect(store.activeSubjectId, retained);

    final Future<void> newer = account.presentActor(_actorB);
    keys.holdActorDelete!.complete();
    await failing;
    await newer;

    expect(store.activeSubjectId, open);
    expect(await store.keys.read(activeProfileItem), open);
    expect(await store.keys.read(AccountController.actorItem(_actorA)), isNull);
    expect(await store.keys.read(profileKeyItem(retained)), isNotNull);
    expect(profileDirectory(retained).existsSync(), isTrue);
    expect(await store.keys.read(AccountController.actorItem(_actorB)), isNull);
    expect(account.actorId, _actorB);
    expect(account.phase, AccountPhase.signedOut);
    expect(account.cloudAccess, isFalse);

    account.beginBind();
    await account.confirmBind();
    expect(store.activeSubjectId, open);
    expect(await store.keys.read(AccountController.actorItem(_actorB)), open);
    expect(profileDirectory(retained).existsSync(), isTrue);
  });

  test('a failed backup exclusion restores the previous profile', () async {
    final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
    var failBackup = false;
    final ProfileStore store = openStore(
      keys: keys,
      excludeFromBackup: (String path) async {
        if (failBackup) {
          failBackup = false;
          throw StateError('backup exclusion failed');
        }
      },
    );
    final AccountController account = AccountController(store: store);
    final String retained = await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    final String open = await store.createProfile();
    failBackup = true;
    keys.holdActorDelete = Completer<void>();
    keys.enteredActorDelete = Completer<void>();

    final Future<void> failing = account.presentActor(_actorA);
    await keys.enteredActorDelete!.future.timeout(const Duration(seconds: 5));
    final Future<void> newer = account.presentActor(_actorB);
    keys.holdActorDelete!.complete();
    await failing;
    await newer;

    expect(store.activeSubjectId, open);
    expect(await store.keys.read(activeProfileItem), open);
    expect(await store.keys.read(AccountController.actorItem(_actorA)), isNull);
    expect(await store.keys.read(profileKeyItem(retained)), isNotNull);
    expect(profileDirectory(retained).existsSync(), isTrue);
    expect(account.actorId, _actorB);
    expect(account.phase, AccountPhase.signedOut);
    expect(account.cloudAccess, isFalse);

    account.beginBind();
    await account.confirmBind();
    expect(await store.keys.read(AccountController.actorItem(_actorB)), open);
  });

  test(
    'a failed mapping cleanup still restores after an active-pointer failure',
    () async {
      await _expectCleanupFailureRestores(failWrite: true);
    },
  );

  test(
    'a failed mapping cleanup still restores after a backup failure',
    () async {
      await _expectCleanupFailureRestores(failWrite: false);
    },
  );
}

Future<void> _expectCleanupFailureRestores({required bool failWrite}) async {
  final Directory temp = Directory.systemTemp.createTempSync(
    'helpmemove-account-cleanup',
  );
  final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
  var failBackup = false;
  final ProfileStore store = ProfileStore(
    keys: keys,
    supportDirectory: temp,
    clock: () => DateTime.utc(2026, 10, 5),
    random: Random(7),
    excludeFromBackup: (String path) async {
      if (failBackup) {
        failBackup = false;
        throw StateError('backup exclusion failed');
      }
    },
  );
  try {
    final AccountController account = AccountController(store: store);
    final String retained = await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    final String open = await store.createProfile();
    if (failWrite) {
      keys.failActiveWrites = 1;
    } else {
      failBackup = true;
    }
    keys.failActorDeletes = 1;
    keys.holdActorDelete = Completer<void>();
    keys.enteredActorDelete = Completer<void>();

    final Future<void> failing = account.presentActor(_actorA);
    await keys.enteredActorDelete!.future.timeout(const Duration(seconds: 5));
    final Future<void> newer = account.presentActor(_actorB);
    keys.holdActorDelete!.complete();
    Object? cleanupError;
    try {
      await failing;
    } on Object catch (error) {
      cleanupError = error;
    }
    await newer;

    expect(cleanupError, isA<StateError>());
    expect(account.phase, isNot(AccountPhase.accessRemoved));
    expect(store.activeSubjectId, open);
    expect(await store.keys.read(activeProfileItem), open);
    expect(await store.keys.read(profileKeyItem(retained)), isNotNull);
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}profiles'
        '${Platform.pathSeparator}$retained',
      ).existsSync(),
      isTrue,
    );
    expect(await store.keys.read(AccountController.actorItem(_actorB)), isNull);

    account.beginBind();
    await account.confirmBind();
    expect(store.activeSubjectId, open);
    expect(await store.keys.read(AccountController.actorItem(_actorB)), open);
    expect(
      await store.keys.read(AccountController.actorItem(_actorA)),
      isNot(open),
    );
  } finally {
    await store.close();
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  }
}

class _HoldKeys implements ProfileKeyStore {
  _HoldKeys(this.inner);

  final MemoryProfileKeyStore inner;
  Completer<void>? holdProfileKey;
  Completer<void>? holdActor;
  Completer<void>? holdActiveDelete;
  Completer<void>? enteredActiveDelete;
  Completer<void>? holdActorDelete;
  Completer<void>? enteredActorDelete;
  Completer<void>? holdSessionDelete;
  Completer<void>? enteredSessionDelete;
  int failActiveWrites = 0;
  int failActorDeletes = 0;

  @override
  Future<String?> read(String item) async {
    final Completer<void>? profileHold = holdProfileKey;
    if (profileHold != null && item.startsWith('profile-key.')) {
      await profileHold.future;
    }
    final Completer<void>? actorHold = holdActor;
    if (actorHold != null && item.startsWith('account-actor.')) {
      await actorHold.future;
    }
    return inner.read(item);
  }

  @override
  Future<void> write(String item, String value) async {
    if (failActiveWrites > 0 && item == activeProfileItem) {
      failActiveWrites -= 1;
      throw StateError('active-profile write failed');
    }
    await inner.write(item, value);
  }

  @override
  Future<void> delete(String item) async {
    final Completer<void>? activeHold = holdActiveDelete;
    if (activeHold != null && item == activeProfileItem) {
      final Completer<void>? entered = enteredActiveDelete;
      if (entered != null && !entered.isCompleted) {
        entered.complete();
      }
      await activeHold.future;
    }
    final Completer<void>? sessionHold = holdSessionDelete;
    if (sessionHold != null && item == supabasePersistSessionKey) {
      final Completer<void>? entered = enteredSessionDelete;
      if (entered != null && !entered.isCompleted) {
        entered.complete();
      }
      await sessionHold.future;
    }
    final Completer<void>? actorHold = holdActorDelete;
    if (actorHold != null && item.startsWith('account-actor.')) {
      final Completer<void>? entered = enteredActorDelete;
      if (entered != null && !entered.isCompleted) {
        entered.complete();
      }
      await actorHold.future;
    }
    if (failActorDeletes > 0 && item.startsWith('account-actor.')) {
      failActorDeletes -= 1;
      throw StateError('actor delete failed');
    }
    await inner.delete(item);
  }
}
