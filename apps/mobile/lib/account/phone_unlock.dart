import 'package:local_auth/local_auth.dart';

/// Shown while the preview is waiting on the phone unlock check.
enum PhoneUnlockGate { checking, unavailable, ready, canceled, unfinished }

/// Result of asking whether this phone can unlock.
enum PhoneUnlockSupport { ready, unavailable, unfinished }

/// Result of the unlock prompt itself.
enum PhoneUnlockDecision { confirmed, canceled, unfinished, unavailable }

const String phoneUnlockReason =
    'Confirm it is you before this profile is copied or removed.';

/// Support check and unlock prompt. Widget tests supply their own result.
abstract class PhoneUnlock {
  Future<PhoneUnlockSupport> isDeviceSupported();

  Future<PhoneUnlockDecision> authenticate();
}

/// Production adapter for `local_auth` 3.0.2.
class ProductionPhoneUnlock implements PhoneUnlock {
  ProductionPhoneUnlock({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<PhoneUnlockSupport> isDeviceSupported() async {
    try {
      final bool supported = await _authentication.isDeviceSupported();
      if (!supported) {
        return PhoneUnlockSupport.unavailable;
      }
      return PhoneUnlockSupport.ready;
    } on LocalAuthException catch (error) {
      if (error.code == LocalAuthExceptionCode.noCredentialsSet) {
        return PhoneUnlockSupport.unavailable;
      }
      return PhoneUnlockSupport.unfinished;
    }
  }

  @override
  Future<PhoneUnlockDecision> authenticate() async {
    try {
      final bool confirmed = await _authentication.authenticate(
        localizedReason: phoneUnlockReason,
        biometricOnly: false,
        persistAcrossBackgrounding: false,
      );
      if (!confirmed) {
        return PhoneUnlockDecision.canceled;
      }
      return PhoneUnlockDecision.confirmed;
    } on LocalAuthException catch (error) {
      if (error.code == LocalAuthExceptionCode.noCredentialsSet) {
        return PhoneUnlockDecision.unavailable;
      }
      if (error.code == LocalAuthExceptionCode.userCanceled ||
          error.code == LocalAuthExceptionCode.systemCanceled ||
          error.code == LocalAuthExceptionCode.timeout) {
        return PhoneUnlockDecision.canceled;
      }
      return PhoneUnlockDecision.unfinished;
    }
  }
}
