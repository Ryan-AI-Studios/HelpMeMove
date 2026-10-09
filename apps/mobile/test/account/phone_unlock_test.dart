import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/account/phone_unlock.dart';
// The production adapter is checked against the plugin platform interface.
// ignore: depend_on_referenced_packages
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

void main() {
  test(
    'production phone unlock uses device credentials and the reason',
    () async {
      final LocalAuthPlatform previous = LocalAuthPlatform.instance;
      final _FakeLocalAuth fake = _FakeLocalAuth();
      LocalAuthPlatform.instance = fake;
      addTearDown(() {
        LocalAuthPlatform.instance = previous;
      });
      final ProductionPhoneUnlock unlock = ProductionPhoneUnlock();
      expect(await unlock.isDeviceSupported(), PhoneUnlockSupport.ready);
      expect(await unlock.authenticate(), PhoneUnlockDecision.confirmed);
      expect(fake.reason, phoneUnlockReason);
      expect(fake.options?.biometricOnly, isFalse);
      expect(fake.options?.stickyAuth, isFalse);

      fake.supported = false;
      expect(await unlock.isDeviceSupported(), PhoneUnlockSupport.unavailable);

      fake.supported = true;
      fake.supportError = const LocalAuthException(
        code: LocalAuthExceptionCode.noCredentialsSet,
      );
      expect(await unlock.isDeviceSupported(), PhoneUnlockSupport.unavailable);

      fake.supportError = null;
      fake.authResult = false;
      expect(await unlock.authenticate(), PhoneUnlockDecision.canceled);

      for (final LocalAuthExceptionCode code in <LocalAuthExceptionCode>[
        LocalAuthExceptionCode.userCanceled,
        LocalAuthExceptionCode.systemCanceled,
        LocalAuthExceptionCode.timeout,
      ]) {
        fake.authError = LocalAuthException(code: code);
        expect(await unlock.authenticate(), PhoneUnlockDecision.canceled);
      }

      fake.authError = const LocalAuthException(
        code: LocalAuthExceptionCode.deviceError,
      );
      expect(await unlock.authenticate(), PhoneUnlockDecision.unfinished);
    },
  );
}

class _FakeLocalAuth extends LocalAuthPlatform {
  bool supported = true;
  bool authResult = true;
  LocalAuthException? supportError;
  LocalAuthException? authError;
  String? reason;
  AuthenticationOptions? options;

  @override
  Future<bool> isDeviceSupported() async {
    final LocalAuthException? error = supportError;
    if (error != null) {
      throw error;
    }
    return supported;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    reason = localizedReason;
    this.options = options;
    final LocalAuthException? error = authError;
    if (error != null) {
      throw error;
    }
    return authResult;
  }
}
