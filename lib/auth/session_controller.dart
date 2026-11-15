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
      // No usable address, so no key can be used. On iOS a reinstall leaves
      // the old Keychain item behind; remove it rather than keep a credential
      // the user cannot reach (see KeyStore.readAll).
      await _deleteOrphanedKeys();
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

  Future<void> _deleteOrphanedKeys() async {
    final all = await _keys.readAll();
    for (final instance in all.keys) {
      await _keys.delete(instance);
    }
  }

  void _setIfMounted(SessionState next) {
    if (ref.mounted) state = next;
  }

  /// Stores [token] for [baseUrl] and signs in.
  ///
  /// Clears any cached answers first, so a previous account on the same server
  /// cannot flash on screen for the new one.
  Future<void> signIn({required Uri baseUrl, required String token}) async {
    final key = baseUrl.toString();
    await _prefs.clearCachedData();
    await _keys.write(key, token);
    await _prefs.setLastBaseUrl(key);
    state = SignedIn(baseUrl: baseUrl, token: token);
  }

  /// Deletes the stored key and shows S1. Revoking the key on the server is
  /// the caller's job and happens before this.
  Future<void> signOut() => _clear(SignedOutReason.userRequested);

  /// A call returned 401: forget the key and show S1 (G3).
  ///
  /// [token] is the key the failed request carried. When it no longer matches
  /// the current session, the 401 belongs to a key the user already replaced
  /// (for example a request that was in flight during sign-out and sign-in)
  /// and must not sign out the new session.
  ///
  /// Safe to call many times; only the first for the current key has an
  /// effect.
  Future<void> handleUnauthorized([String? token]) {
    final current = state;
    if (token != null &&
        current is SignedIn &&
        !current.isDemo &&
        current.token != token) {
      return Future<void>.value();
    }
    return _clear(SignedOutReason.expired);
  }

  Future<void> _clear(SignedOutReason reason) async {
    final current = state;
    if (current is! SignedIn || current.isDemo) return;
    final baseKey = current.baseUrl.toString();
    final token = current.token;
    // Switch state first so late responses and a second 401 do nothing.
    state = SignedOut(lastBaseUrl: baseKey, reason: reason);
    await _prefs.clearCachedData();
    if (state is SignedIn) return;
    // A very fast sign-in on the same URL may already have written a new key.
    // Only delete the key this sign-out belongs to.
    final stored = await _keys.read(baseKey);
    if (stored == token) await _keys.delete(baseKey);
  }
}

/// The session.
final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
