import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/base_url.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/data/fake/demo_data.dart';

/// The board-key store. Defaults to the platform keystore; tests override it.
final keyStoreProvider = Provider<KeyStore>((ref) => SecureKeyStore());

/// Preferences. `main` overrides this with the loaded instance.
final appPrefsProvider = Provider<AppPrefs>(
  (ref) => throw StateError('appPrefsProvider must be overridden.'),
);

/// Owns the signed-in state and the board key.
///
/// Any 401 calls [handleUnauthorized]: the key is deleted and the router sends
/// the user to S1 with the address prefilled (PRD G3).
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final env = ref.watch(appEnvProvider);
    if (env.demo) return SignedIn.demo(Uri.parse(demoBaseUrl));
    // After build returns: state set inside build would be overwritten by
    // its return value.
    unawaited(Future<void>.microtask(_restore));
    return const SessionRestoring();
  }

  KeyStore get _keys => ref.read(keyStoreProvider);
  AppPrefs get _prefs => ref.read(appPrefsProvider);

  Future<void> _restore() async {
    final lastUrl = _prefs.lastBaseUrl;
    final parsed = lastUrl == null ? null : BaseUrl.parse(lastUrl);
    if (parsed is! BaseUrlOk) {
      _setIfMounted(const SignedOut());
      return;
    }
    final token = await _keys.read(parsed.key);
    _setIfMounted(
      token == null || token.isEmpty
          ? SignedOut(lastBaseUrl: parsed.key)
          : SignedIn(baseUrl: parsed.uri, token: token),
    );
  }

  void _setIfMounted(SessionState next) {
    if (ref.mounted) state = next;
  }

  /// Stores [token] for [baseUrl] and signs in.
  Future<void> signIn({required Uri baseUrl, required String token}) async {
    final key = baseUrl.toString();
    await _keys.write(key, token);
    await _prefs.setLastBaseUrl(key);
    state = SignedIn(baseUrl: baseUrl, token: token);
  }

  /// Deletes the stored key and shows S1. Revoking the key on the server is
  /// the caller's job and happens before this.
  Future<void> signOut() => _clear(SignedOutReason.userRequested);

  /// A call with the key returned 401: forget the key and show S1 (G3).
  /// Safe to call many times; only the first has an effect.
  Future<void> handleUnauthorized() => _clear(SignedOutReason.expired);

  Future<void> _clear(SignedOutReason reason) async {
    final current = state;
    if (current is! SignedIn || current.isDemo) return;
    // Switch state first so late responses and a second 401 do nothing.
    state = SignedOut(lastBaseUrl: current.baseUrl.toString(), reason: reason);
    await _keys.delete(current.baseUrl.toString());
  }
}

/// The session.
final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
