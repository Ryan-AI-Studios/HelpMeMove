import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  test('bridge version is the abi marker', () {
    expect(bridgeVersion(), 'helpmemove-bridge-1');
  });

  test('accepts the smoke subject', () {
    expect(acceptSubject(raw: 'subject-smoke-1'), 'subject-smoke-1');
  });

  test('rejects non-finite confidence and a cancel flag', () {
    expect(
      () => acceptConfidence(value: double.nan),
      throwsA(BridgeError.invalidConfidence),
    );
    expect(
      () => acceptConfidence(value: double.infinity),
      throwsA(BridgeError.invalidConfidence),
    );
    expect(
      () => observeCancel(cancelled: true),
      throwsA(BridgeError.cancelled),
    );
  });

  test('contained panic leaves the library usable', () {
    expect(probeContainedPanic, throwsA(isA<PanicException>()));
    expect(bridgeVersion(), 'helpmemove-bridge-1');
  });
}
