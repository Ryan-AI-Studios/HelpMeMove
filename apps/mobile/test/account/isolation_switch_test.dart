import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/account/account_controller.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';

const String _actorA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const String _program = '{"record_version":1,"rule_id":"syn-program-core"}';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-isolation-switch');
  });

  tearDown(() async {
    await live?.close();
    live = null;
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  ProfileStore openStore() {
    final ProfileStore store = ProfileStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 10, 6),
      random: Random(7),
      excludeFromBackup: (String path) async {},
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

  test('a pending outbox stays on the first subject after a switch', () async {
    final ProfileStore store = openStore();
    final String first = await store.createProfile();
    final AccountController account = AccountController(
      store: store,
      sendCopy:
          ({
            required String entity,
            required String eventId,
            required String documentText,
            required String documentSha256,
          }) async {
            return 'confirmed';
          },
      sessionReady: () => false,
    );
    await account.presentActor(_actorA);
    account.beginBind();
    await account.confirmBind();
    await store.saveProgramRecord(_program);
    await account.bringItOver();

    final List<SyncOutboxPendingItem> firstPending = await store
        .loadPendingOutbox(first);
    expect(firstPending, hasLength(1));
    final String eventId = firstPending.single.eventId;

    final String second = await store.createProfile();
    expect(store.activeSubjectId, second);
    expect(await store.loadPendingOutbox(second), isEmpty);

    await account.presentActor(_actorA);
    expect(store.activeSubjectId, first);
    final List<SyncOutboxPendingItem> restored = await store.loadPendingOutbox(
      first,
    );
    expect(restored, hasLength(1));
    expect(restored.single.eventId, eventId);
    expect(profileDirectory(second).existsSync(), isTrue);
  });
}
