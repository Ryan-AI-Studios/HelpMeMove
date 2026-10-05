import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session string in the profile key store.
///
/// The package constant is the item name. The platform preference store is
/// not used.
class SecureSessionStore extends LocalStorage {
  SecureSessionStore(this._keys);

  final ProfileKeyStore _keys;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() {
    return _keys.read(supabasePersistSessionKey);
  }

  @override
  Future<bool> hasAccessToken() async {
    final String? session = await accessToken();
    return session != null;
  }

  @override
  Future<void> persistSession(String persistSessionString) {
    return _keys.write(supabasePersistSessionKey, persistSessionString);
  }

  @override
  Future<void> removePersistedSession() {
    return _keys.delete(supabasePersistSessionKey);
  }
}

/// Holds the PKCE code verifier in the profile key store.
///
/// supabase_flutter 2.18.0 substitutes its platform preference store when
/// `pkceAsyncStorage` is omitted. Passing this store keeps the verifier in
/// the profile key store.
class SecurePkceStore extends GotrueAsyncStorage {
  SecurePkceStore(this._keys);

  final ProfileKeyStore _keys;

  static const String _prefix = 'pkce.';

  @override
  Future<String?> getItem({required String key}) {
    return _keys.read('$_prefix$key');
  }

  @override
  Future<void> setItem({required String key, required String value}) {
    return _keys.write('$_prefix$key', value);
  }

  @override
  Future<void> removeItem({required String key}) {
    return _keys.delete('$_prefix$key');
  }
}
