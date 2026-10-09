import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/account/account_auth.dart';
import 'package:helpmemove/account/account_controller.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';

const String _actorA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const String _program = '{"record_version":1,"rule_id":"syn-program-core"}';
const String _sessionId = '11111111-1111-4111-8111-111111111111';
const String _workout = '{"session_id":"11111111-1111-4111-8111-111111111111"}';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-sync-copy');
  });

  tearDown(() async {
    await live?.close();
    live = null;
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  ProfileStore openStore({
    Future<void> Function(String path)? excludeFromBackup,
  }) {
    final ProfileStore store = ProfileStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 5),
      random: Random(7),
      excludeFromBackup: excludeFromBackup ?? (String path) async {},
    );
    live = store;
    return store;
  }

  Future<AccountController> bindPreview(
    ProfileStore store, {
    CopySend? sendCopy,
    bool Function()? sessionReady,
  }) async {
    final AccountController account = AccountController(
      store: store,
      sendCopy: sendCopy,
      sessionReady: sessionReady ?? () => true,
    );
    await store.createProfile();
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    expect(account.phase, AccountPhase.signedIn);
    expect(account.copyPreview, isTrue);
    expect(account.copyAccepted, isFalse);
    return account;
  }

  test(
    'bringItOver seeds pending outbox rows for program and workout',
    () async {
      final ProfileStore store = openStore();
      await store.createProfile();
      await store.saveProgramRecord(_program);
      await store.saveWorkoutTerminal(
        sessionId: _sessionId,
        documentJson: _workout,
      );
      final AccountController account = AccountController(
        store: store,
        sendCopy: ({
          required String entity,
          required String eventId,
          required String documentText,
          required String documentSha256,
        }) async => 'unavailable',
        sessionReady: () => false,
      );
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      await account.bringItOver();
      final String subject = store.activeSubjectId!;
      final List<SyncOutboxPendingItem> pending = await store.loadPendingOutbox(
        subject,
      );
      expect(pending, hasLength(2));
      expect(
        pending.map((SyncOutboxPendingItem item) => item.entity).toSet(),
        <String>{'program_records', 'workout_records'},
      );
      expect(store.isCopyAccepted(subject), isTrue);
      expect(account.copyAccepted, isTrue);
      expect(account.copyPreview, isFalse);
    },
  );

  test('Not now inserts nothing', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    await store.saveProgramRecord(_program);
    final AccountController account = await bindPreview(store);
    account.cancelCopy();
    expect(account.copyPreview, isFalse);
    expect(account.copyNotice, copyCancelNotice);
    expect(await store.loadPendingOutbox(store.activeSubjectId!), isEmpty);
  });

  test('Try again with sessionReady false does not call sendCopy', () async {
    var sent = 0;
    final ProfileStore store = openStore();
    final AccountController account = await bindPreview(
      store,
      sendCopy:
          ({
            required String entity,
            required String eventId,
            required String documentText,
            required String documentSha256,
          }) async {
            sent += 1;
            return 'confirmed';
          },
      sessionReady: () => false,
    );
    account.copyNotice = copyInterruptedNotice;
    await account.retryCopy();
    expect(sent, 0);
    expect(account.copyNotice, copyInterruptedNotice);
  });

  test('sessionReady false does not call sendCopy on bringItOver', () async {
    var sent = 0;
    final ProfileStore store = openStore();
    await store.createProfile();
    await store.saveProgramRecord(_program);
    final AccountController account = AccountController(
      store: store,
      sendCopy:
          ({
            required String entity,
            required String eventId,
            required String documentText,
            required String documentSha256,
          }) async {
            sent += 1;
            return 'confirmed';
          },
      sessionReady: () => false,
    );
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    await account.bringItOver();
    expect(sent, 0);
    expect(account.copyNotice, copyInterruptedNotice);
    expect(await store.loadPendingOutbox(store.activeSubjectId!), hasLength(1));
  });

  test(
    'sendCopy confirmed, rejected, unavailable, throw, and other text',
    () async {
      Future<void> runResult(
        String Function() result, {
        Object? throwError,
      }) async {
        final Directory local = Directory.systemTemp.createTempSync(
          'helpmemove-copy-result',
        );
        final ProfileStore store = ProfileStore(
          keys: MemoryProfileKeyStore(),
          supportDirectory: local,
          clock: () => DateTime.utc(2026, 10, 5),
          random: Random(11),
          excludeFromBackup: (String path) async {},
        );
        try {
          var sent = 0;
          final AccountController account = AccountController(
            store: store,
            sendCopy:
                ({
                  required String entity,
                  required String eventId,
                  required String documentText,
                  required String documentSha256,
                }) async {
                  sent += 1;
                  if (throwError != null) {
                    throw throwError;
                  }
                  return result();
                },
            sessionReady: () => true,
          );
          await store.createProfile();
          await store.saveProgramRecord(_program);
          await account.presentActor(_actorA);
          account.beginBind();
          await account.confirmBind();
          await account.bringItOver();
          expect(sent, 1);
          final List<SyncOutboxPendingItem> pending = await store
              .loadPendingOutbox(store.activeSubjectId!);
          final String outcome = throwError != null ? 'throw' : result();
          if (outcome == 'confirmed' || outcome == 'rejected') {
            expect(pending, isEmpty);
            expect(account.copyNotice, isNull);
          } else {
            expect(pending, hasLength(1));
            if (outcome == 'unavailable' || throwError != null) {
              expect(account.copyNotice, copyInterruptedNotice);
            } else {
              expect(account.copyNotice, isNull);
            }
          }
          if (outcome == 'rejected') {
            expect(account.copyNotice, isNull);
          }
        } finally {
          await store.close();
          if (local.existsSync()) {
            local.deleteSync(recursive: true);
          }
        }
      }

      await runResult(() => 'confirmed');
      await runResult(() => 'rejected');
      await runResult(() => 'unavailable');
      await runResult(() => 'confirmed', throwError: StateError('network'));
      await runResult(() => 'weird');
    },
  );

  test('overlapping onOutboxEnqueued waits for the first sendCopy', () async {
    final Completer<String> first = Completer<String>();
    final List<String> started = <String>[];
    final ProfileStore store = openStore();
    await store.createProfile();
    await store.saveProgramRecord(_program);
    final AccountController account = AccountController(
      store: store,
      sendCopy:
          ({
            required String entity,
            required String eventId,
            required String documentText,
            required String documentSha256,
          }) async {
            started.add(eventId);
            if (started.length == 1) {
              return first.future;
            }
            return 'confirmed';
          },
      sessionReady: () => true,
    );
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    final Future<void> copying = account.bringItOver();
    for (var attempt = 0; attempt < 50 && started.isEmpty; attempt++) {
      await pumpEventQueue();
    }
    expect(started, hasLength(1));
    await store.saveWorkoutTerminal(
      sessionId: _sessionId,
      documentJson: _workout,
    );
    await pumpEventQueue();
    expect(started, hasLength(1));
    first.complete('confirmed');
    await copying;
    expect(started, hasLength(2));
    expect(started.first, isNot(started.last));
  });

  test(
    'expire during the first sendCopy does not send the second row',
    () async {
      final Completer<String> first = Completer<String>();
      final List<String> started = <String>[];
      final ProfileStore store = openStore();
      await store.createProfile();
      await store.saveProgramRecord(_program);
      await store.saveWorkoutTerminal(
        sessionId: _sessionId,
        documentJson: _workout,
      );
      final AccountController account = AccountController(
        store: store,
        sendCopy:
            ({
              required String entity,
              required String eventId,
              required String documentText,
              required String documentSha256,
            }) async {
              started.add(eventId);
              if (started.length == 1) {
                return first.future;
              }
              return 'confirmed';
            },
        sessionReady: () => true,
      );
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      final Future<void> copying = account.bringItOver();
      for (var attempt = 0; attempt < 50 && started.isEmpty; attempt++) {
        await pumpEventQueue();
      }
      expect(started, hasLength(1));
      await account.expire();
      first.complete('confirmed');
      await copying;
      await pumpEventQueue();
      expect(started, hasLength(1));
      expect(store.onOutboxEnqueued, isNull);
    },
  );

  test(
    'an unmapped presentActor drops the copy worker before signedOut',
    () async {
      const String unmapped = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      final List<String> sent = <String>[];
      final ProfileStore store = openStore();
      await store.createProfile();
      await store.saveProgramRecord(_program);
      final AccountController account = AccountController(
        store: store,
        sendCopy:
            ({
              required String entity,
              required String eventId,
              required String documentText,
              required String documentSha256,
            }) async {
              sent.add(eventId);
              return 'confirmed';
            },
        sessionReady: () => false,
      );
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      await account.bringItOver();
      expect(store.onOutboxEnqueued, isNotNull);
      expect(sent, isEmpty);
      await account.presentActor(unmapped);
      expect(account.phase, AccountPhase.signedOut);
      expect(store.onOutboxEnqueued, isNull);
      await store.saveWorkoutTerminal(
        sessionId: _sessionId,
        documentJson: _workout,
      );
      await pumpEventQueue();
      expect(sent, isEmpty);
    },
  );

  test('an empty drain with no session clears copyNotice', () async {
    final ProfileStore store = openStore();
    final List<String> sent = <String>[];
    final AccountController account = await bindPreview(
      store,
      sendCopy:
          ({
            required String entity,
            required String eventId,
            required String documentText,
            required String documentSha256,
          }) async {
            sent.add(eventId);
            return 'confirmed';
          },
      sessionReady: () => false,
    );
    await account.bringItOver();
    expect(sent, isEmpty);
    expect(account.copyNotice, isNull);
    expect(account.copyPreview, isFalse);
    expect(account.copyAccepted, isTrue);
  });

  test('production sessionReady checks AccountAuth.started first', () async {
    final String source = File('lib/account/account_controller.dart')
        .readAsStringSync();
    final int readyAt = source.indexOf('bool productionSessionReady()');
    final int sendAt = source.indexOf('Future<String> productionSendCopy');
    expect(readyAt, greaterThanOrEqualTo(0));
    expect(sendAt, greaterThan(readyAt));
    final String readyBody = source.substring(readyAt, sendAt);
    expect(readyBody.contains('AccountAuth.started'), isTrue);
    expect(
      readyBody.indexOf('AccountAuth.started'),
      lessThan(readyBody.indexOf('Supabase.instance')),
    );
    AccountAuth.started = false;
    final ProfileStore store = openStore();
    await store.createProfile();
    final AccountController account = AccountController(store: store);
    expect(account.sessionReady(), isFalse);
  });

  test('production sendCopy source names copy_owned_document params', () {
    final String source = File('lib/account/account_controller.dart')
        .readAsStringSync();
    expect(source.contains("rpc('copy_owned_document', params:"), isTrue);
    expect(source.contains("'p_entity'"), isTrue);
    expect(source.contains("'p_event_id'"), isTrue);
    expect(source.contains("'p_document_text'"), isTrue);
    expect(source.contains("'p_document_sha256'"), isTrue);
  });

  test('expire and removeAccess cancel the copy worker', () async {
    final ProfileStore store = openStore();
    final AccountController account = await bindPreview(
      store,
      sessionReady: () => false,
    );
    await store.markCopyAccepted(store.activeSubjectId!);
    account.copyPreview = false;
    account.copyAccepted = true;
    await account.presentActor(_actorA);
    final AccountSubscription subscription = account.listen(() {});
    final int before = account.generation;
    await account.expire();
    expect(subscription.cancelled, isTrue);
    expect(account.generation, greaterThan(before));
    expect(account.copyNotice, copyInterruptedNotice);
    expect(store.onOutboxEnqueued, isNull);

    account.copyNotice = 'kept';
    final AccountSubscription next = account.listen(() {});
    final int generation = account.generation;
    await account.removeAccess();
    expect(next.cancelled, isTrue);
    expect(account.generation, greaterThan(generation));
    expect(account.copyNotice, copyInterruptedNotice);
  });

  test('keepLocked and removeLocal clear copyNotice', () async {
    final ProfileStore store = openStore();
    final AccountController locked = await bindPreview(store);
    locked.copyNotice = copyInterruptedNotice;
    await locked.keepLocked();
    expect(locked.copyNotice, isNull);
    await store.close();
    live = null;

    final Directory otherDir = Directory.systemTemp.createTempSync(
      'helpmemove-sync-copy-remove',
    );
    final ProfileStore other = ProfileStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: otherDir,
      clock: () => DateTime.utc(2026, 10, 5),
      random: Random(7),
      excludeFromBackup: (String path) async {},
    );
    try {
      final AccountController removed = await bindPreview(other);
      removed.copyNotice = copyInterruptedNotice;
      await removed.removeLocal();
      expect(removed.copyNotice, isNull);
    } finally {
      await other.close();
      if (otherDir.existsSync()) {
        otherDir.deleteSync(recursive: true);
      }
    }
  });

  test('rejected does not set copyNotice', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    await store.saveProgramRecord(_program);
    final AccountController account = AccountController(
      store: store,
      sendCopy: ({
        required String entity,
        required String eventId,
        required String documentText,
        required String documentSha256,
      }) async => 'rejected',
      sessionReady: () => true,
    );
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    await account.bringItOver();
    expect(account.copyNotice, isNull);
    expect(await store.loadPendingOutbox(store.activeSubjectId!), isEmpty);
  });

  test(
    'failed markCopyAccepted leaves copyPreview true and sends nothing',
    () async {
      var failBackup = false;
      var sent = 0;
      final ProfileStore store = openStore(
        excludeFromBackup: (String path) async {
          if (failBackup) {
            throw StateError('backup exclusion failed');
          }
        },
      );
      await store.createProfile();
      await store.saveProgramRecord(_program);
      final AccountController account = AccountController(
        store: store,
        sendCopy:
            ({
              required String entity,
              required String eventId,
              required String documentText,
              required String documentSha256,
            }) async {
              sent += 1;
              return 'confirmed';
            },
        sessionReady: () => true,
      );
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      failBackup = true;
      await account.bringItOver();
      expect(account.copyPreview, isTrue);
      expect(account.copyAccepted, isFalse);
      expect(sent, 0);
      expect(store.onOutboxEnqueued, isNull);
      expect(store.isCopyAccepted(store.activeSubjectId!), isFalse);
      await account.presentActor(_actorA);
      expect(sent, 0);
      expect(account.copyPreview, isTrue);
      expect(store.onOutboxEnqueued, isNull);
    },
  );

  test('router still constructs AccountController with the profile store', () {
    final String source = File('lib/design/router.dart').readAsStringSync();
    expect(source.contains('store: profile'), isTrue);
    expect(source.contains('phoneUnlock: phoneUnlock'), isTrue);
  });

  test('requestReauth does not drop copy state', () async {
    final ProfileStore store = openStore();
    final AccountController account = await bindPreview(store);
    account.copyNotice = copyCancelNotice;
    final bool preview = account.copyPreview;
    final bool accepted = account.copyAccepted;
    account.requestReauth(() {});
    expect(account.copyPreview, preview);
    expect(account.copyAccepted, accepted);
    expect(account.copyNotice, copyCancelNotice);
    account.cancelReauth();
    expect(account.phase, AccountPhase.signedIn);
    expect(account.copyPreview, preview);
  });

  test(
    'a newer actor does not send the open profile during the map read',
    () async {
      var sent = 0;
      final _HoldKeys keys = _HoldKeys(MemoryProfileKeyStore());
      final ProfileStore store = ProfileStore(
        keys: keys,
        supportDirectory: temp,
        clock: () => DateTime.utc(2026, 10, 5),
        random: Random(7),
        excludeFromBackup: (String path) async {},
      );
      live = store;
      await store.createProfile();
      await store.saveProgramRecord(_program);
      final AccountController account = AccountController(
        store: store,
        sendCopy:
            ({
              required String entity,
              required String eventId,
              required String documentText,
              required String documentSha256,
            }) async {
              sent += 1;
              return 'unavailable';
            },
        sessionReady: () => true,
      );
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      await account.bringItOver();
      expect(sent, 1);
      final String subject = store.activeSubjectId!;
      final Completer<void> gate = Completer<void>();
      keys.holdNextRead = gate;
      final Future<void> presenting = account.presentActor(
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      );
      var spins = 0;
      while (!keys.waiting && spins < 50) {
        await Future<void>.delayed(Duration.zero);
        spins += 1;
      }
      expect(keys.waiting, isTrue);
      store.onOutboxEnqueued?.call();
      for (var i = 0; i < 10; i += 1) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(sent, 1);
      expect(await store.loadPendingOutbox(subject), hasLength(1));
      gate.complete();
      await presenting;
      expect(sent, 1);
    },
  );

  test('Not now during backup exclusion sends nothing', () async {
    final Completer<void> gate = Completer<void>();
    var holdBackup = false;
    var waiting = false;
    var sent = 0;
    final ProfileStore store = openStore(
      excludeFromBackup: (String path) async {
        if (!holdBackup) {
          return;
        }
        waiting = true;
        await gate.future;
      },
    );
    await store.createProfile();
    await store.saveProgramRecord(_program);
    final AccountController account = AccountController(
      store: store,
      sendCopy:
          ({
            required String entity,
            required String eventId,
            required String documentText,
            required String documentSha256,
          }) async {
            sent += 1;
            return 'confirmed';
          },
      sessionReady: () => true,
    );
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    final String subject = store.activeSubjectId!;
    holdBackup = true;
    final Future<void> copying = account.bringItOver();
    var spins = 0;
    while (!waiting && spins < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      spins += 1;
    }
    expect(waiting, isTrue);
    account.cancelCopy();
    gate.complete();
    await copying;
    expect(sent, 0);
    expect(store.isCopyAccepted(subject), isFalse);
    expect(account.copyAccepted, isFalse);
    expect(account.copyNotice, copyCancelNotice);
    expect(store.onOutboxEnqueued, isNull);
  });

  test('reopening the preview does not revive a cancelled copy', () async {
    final Completer<void> gate = Completer<void>();
    var holdBackup = false;
    var waiting = false;
    var sent = 0;
    final ProfileStore store = openStore(
      excludeFromBackup: (String path) async {
        if (!holdBackup) {
          return;
        }
        waiting = true;
        await gate.future;
      },
    );
    await store.createProfile();
    await store.saveProgramRecord(_program);
    final AccountController account = AccountController(
      store: store,
      sendCopy:
          ({
            required String entity,
            required String eventId,
            required String documentText,
            required String documentSha256,
          }) async {
            sent += 1;
            return 'confirmed';
          },
      sessionReady: () => true,
    );
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    final String subject = store.activeSubjectId!;
    holdBackup = true;
    final Future<void> copying = account.bringItOver();
    var spins = 0;
    while (!waiting && spins < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      spins += 1;
    }
    expect(waiting, isTrue);
    account.cancelCopy();
    account.openCopyPreview();
    expect(account.copyPreview, isTrue);
    gate.complete();
    await copying;
    expect(sent, 0);
    expect(store.isCopyAccepted(subject), isFalse);
    expect(account.copyPreview, isTrue);
    expect(store.onOutboxEnqueued, isNull);
  });

  test(
    'a cancelled marker failure does not bind on the next sign-in',
    () async {
      final Completer<void> gate = Completer<void>();
      var holdBackup = false;
      var waiting = false;
      var sent = 0;
      final ProfileStore store = openStore(
        excludeFromBackup: (String path) async {
          if (!holdBackup) {
            return;
          }
          waiting = true;
          await gate.future;
          throw StateError('backup exclusion failed');
        },
      );
      await store.createProfile();
      await store.saveProgramRecord(_program);
      final AccountController account = AccountController(
        store: store,
        sendCopy:
            ({
              required String entity,
              required String eventId,
              required String documentText,
              required String documentSha256,
            }) async {
              sent += 1;
              return 'confirmed';
            },
        sessionReady: () => true,
      );
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      final String subject = store.activeSubjectId!;
      holdBackup = true;
      final Future<void> copying = account.bringItOver();
      var spins = 0;
      while (!waiting && spins < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        spins += 1;
      }
      expect(waiting, isTrue);
      account.cancelCopy();
      gate.complete();
      await copying;
      expect(sent, 0);
      expect(store.isCopyAccepted(subject), isFalse);
      await account.presentActor(_actorA);
      expect(sent, 0);
      expect(account.copyPreview, isTrue);
      expect(store.onOutboxEnqueued, isNull);
    },
  );

  test(
    'cancelling during the sweep does not bind after the preview reopens',
    () async {
      final Completer<void> gate = Completer<void>();
      var waiting = false;
      var sent = 0;
      final ProfileStore store = openStore();
      await store.createProfile();
      await store.saveProgramRecord(_program);
      store.onBeforeSweepCopy = () async {
        waiting = true;
        await gate.future;
      };
      final AccountController account = AccountController(
        store: store,
        sendCopy:
            ({
              required String entity,
              required String eventId,
              required String documentText,
              required String documentSha256,
            }) async {
              sent += 1;
              return 'confirmed';
            },
        sessionReady: () => true,
      );
      await account.presentActor(_actorA);
      account.beginBind();
      await account.confirmBind();
      final String subject = store.activeSubjectId!;
      final Future<void> copying = account.bringItOver();
      var spins = 0;
      while (!waiting && spins < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        spins += 1;
      }
      expect(waiting, isTrue);
      account.cancelCopy();
      account.openCopyPreview();
      gate.complete();
      await copying;
      expect(sent, 0);
      expect(store.isCopyAccepted(subject), isFalse);
      expect(account.copyPreview, isTrue);
      expect(store.onOutboxEnqueued, isNull);
    },
  );

  test('a missing document does not clear the interruption notice', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    await store.saveProgramRecord(_program);
    final AccountController account = AccountController(
      store: store,
      sendCopy: ({
        required String entity,
        required String eventId,
        required String documentText,
        required String documentSha256,
      }) async => 'unavailable',
      sessionReady: () => true,
    );
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    await account.bringItOver();
    expect(account.copyNotice, copyInterruptedNotice);
    final String subject = store.activeSubjectId!;
    await store.deleteProgramRecord();
    expect(await store.loadPendingOutbox(subject), isEmpty);
    await account.retryCopy();
    expect(await store.hasPendingOutbox(subject), isTrue);
    expect(account.copyNotice, copyInterruptedNotice);
  });
}

class _HoldKeys implements ProfileKeyStore {
  _HoldKeys(this._inner);

  final MemoryProfileKeyStore _inner;
  Completer<void>? holdNextRead;
  bool waiting = false;

  @override
  Future<String?> read(String item) async {
    final Completer<void>? hold = holdNextRead;
    if (hold != null) {
      waiting = true;
      await hold.future;
    }
    return _inner.read(item);
  }

  @override
  Future<void> write(String item, String value) {
    return _inner.write(item, value);
  }

  @override
  Future<void> delete(String item) {
    return _inner.delete(item);
  }
}
