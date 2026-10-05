import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/account/account_auth.dart';
import 'package:helpmemove/account/account_screen.dart';
import 'package:helpmemove/account/secure_session_store.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('empty dart-defines do not initialize Supabase', () async {
    await AccountAuth.start();
    expect(AccountAuth.started, isFalse);
  });

  test(
    'the session string is written only to the injected key store',
    () async {
      final MemoryProfileKeyStore keys = MemoryProfileKeyStore();
      await keys.write('profile-key.p-abc', 'kept');
      final SecureSessionStore session = SecureSessionStore(keys);
      await session.initialize();
      expect(await session.hasAccessToken(), isFalse);

      await session.persistSession('session-value');
      expect(keys.values[supabasePersistSessionKey], 'session-value');
      expect(keys.values['profile-key.p-abc'], 'kept');
      expect(keys.values.length, 2);
      expect(await session.accessToken(), 'session-value');
      expect(await session.hasAccessToken(), isTrue);

      await session.removePersistedSession();
      expect(keys.values.containsKey(supabasePersistSessionKey), isFalse);
      expect(keys.values['profile-key.p-abc'], 'kept');

      final SecurePkceStore pkce = SecurePkceStore(keys);
      await pkce.setItem(key: 'verifier', value: 'code');
      expect(keys.values['pkce.verifier'], 'code');
      expect(keys.values.containsKey(supabasePersistSessionKey), isFalse);
      expect(await pkce.getItem(key: 'verifier'), 'code');
      await pkce.removeItem(key: 'verifier');
      expect(keys.values.containsKey('pkce.verifier'), isFalse);
    },
  );

  test('account sources avoid shared preferences and extra providers', () {
    final String session = File('lib/account/secure_session_store.dart')
        .readAsStringSync();
    final String auth = File('lib/account/account_auth.dart')
        .readAsStringSync();
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final String database = File('lib/storage/profile_database.dart')
        .readAsStringSync();
    final String entry = File('lib/main.dart').readAsStringSync();

    expect(session.contains('package:shared_preferences'), isFalse);
    expect(session.contains('SharedPreferencesLocalStorage'), isFalse);
    expect(session.contains('supabasePersistSessionKey'), isTrue);
    expect(auth.contains('package:shared_preferences'), isFalse);
    expect(auth.contains('SharedPreferencesLocalStorage'), isFalse);
    expect(auth.contains('detectSessionInUri: false'), isTrue);
    expect(auth.contains('publishableKey: publishableKey'), isTrue);
    expect(auth.contains('anonKey'), isFalse);
    expect(auth.contains('SUPABASE_URL'), isTrue);
    expect(auth.contains('SUPABASE_PUBLISHABLE_KEY'), isTrue);
    expect(entry.contains('AccountAuth.start()'), isTrue);
    expect(pubspec.contains('supabase_flutter: 2.18.0'), isTrue);
    expect(pubspec.contains('sign_in_with_apple'), isFalse);
    expect(pubspec.contains('google_sign_in'), isFalse);
    expect(pubspec.contains('flutter_secure_storage: 11.2.0'), isTrue);
    expect(database.contains('int get schemaVersion => 9;'), isTrue);
  });

  test('a token, email, or session query is unavailable', () {
    expect(accountLinkIsUnavailable(Uri.parse('/focus/account')), isFalse);
    expect(
      accountLinkIsUnavailable(Uri.parse('/focus/account?token=')),
      isFalse,
    );
    expect(
      accountLinkIsUnavailable(Uri.parse('/focus/account?token=secret')),
      isTrue,
    );
    expect(
      accountLinkIsUnavailable(
        Uri.parse('/focus/account?email=a@example.test'),
      ),
      isTrue,
    );
    expect(
      accountLinkIsUnavailable(Uri.parse('/focus/account?session=abc')),
      isTrue,
    );
    expect(
      accountLinkIsUnavailable(Uri.parse('/focus/account?step=ready')),
      isFalse,
    );
  });
}
