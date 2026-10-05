import 'package:helpmemove/account/secure_session_store.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Starts Supabase only when both local dart-defines are set.
///
/// The committed app and CI leave `SUPABASE_URL` and
/// `SUPABASE_PUBLISHABLE_KEY` empty, so this returns without initializing.
class AccountAuth {
  static bool started = false;

  static Future<void> start({ProfileKeyStore? keys}) async {
    const String url = String.fromEnvironment('SUPABASE_URL');
    const String publishableKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    );
    if (url.isEmpty || publishableKey.isEmpty) {
      started = false;
      return;
    }
    final ProfileKeyStore store =
        keys ?? SecureProfileKeyStore(productionSecureStorage());
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSessionStore(store),
        pkceAsyncStorage: SecurePkceStore(store),
        detectSessionInUri: false,
      ),
    );
    started = true;
  }
}
