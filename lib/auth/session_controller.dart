import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/base_url.dart';
import 'package:paperplane/api/models/board_key.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/device_name.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/auth/stored_key.dart';
import 'package:paperplane/core/clock.dart';
import 'package:paperplane/data/auth_repository.dart';
import 'package:paperplane/data/fake/demo_data.dart';

/// The board-key store. Defaults to the platform keystore; tests override it.
final keyStoreProvider = Provider<KeyStore>((ref) => SecureKeyStore());

/// Preferences. `main` overrides this with the loaded instance.
final appPrefsProvider = Provider<AppPrefs>(
  (ref) => throw StateError('appPrefsProvider must be overridden.'),
);

/// Mints and revokes keys during rotation. Tests override it with a
/// repository that has a fake adapter.
final keyRotationRepositoryProvider = Provider<AuthRepository>(
  (ref) => HttpAuthRepository(),
);

/// Name of a key minted by rotation. The same label as the first key.
final keyNameProvider = Provider<String>(
  (ref) => keyNameForDevice(platformDeviceName()),
);

/// Owns the signed-in state and the board key.
///
/// Any 401 calls [handleUnauthorized]: the key is deleted and the router sends
/// the user to S1 with the address prefilled (PRD G3).
///
/// A key the app created is replaced after seven days, silently, using the
/// still-valid key (PRD S1 AC9). The new key is stored before the old one is
/// revoked, so a failed mint or store keeps the old key working.
class SessionController extends Notifier<SessionState> {
  /// How old a key may be before the app replaces it.
  static const rotationAge = Duration(days: 7);

  int _generation = 0;
  String? _rotatingToken;
  Future<void>? _rotation;

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
  DateTime _now() => ref.read(clockProvider)();

  Future<void> _restore() async {
    final lastUrl = _prefs.lastBaseUrl;
    final parsed = lastUrl == null ? null : BaseUrl.parse(lastUrl);
    try {
      if (parsed is! BaseUrlOk) {
        // No usable address, so no key can be used. On iOS a reinstall leaves
        // the old Keychain item behind; remove it rather than keep a
        // credential the user cannot reach (see KeyStore.readAll).
        await _deleteOrphanedKeys();
        _setIfMounted(const SignedOut());
        return;
      }
      final stored = await _keys.read(parsed.key);
      if (stored == null || !stored.isUsable) {
        _setIfMounted(SignedOut(lastBaseUrl: parsed.key));
        return;
      }
      final current = await _migrateLegacy(parsed.key, stored);
      _setIfMounted(SignedIn(baseUrl: parsed.uri, token: current.token));
      unawaited(rotateIfNeeded());
    } on Object catch (error) {
      // A keystore failure must never leave the app on the splash. There is no
      // timeout: on a Mac the login keychain can wait for an OS permission
      // prompt, and denying it throws here.
      _logKeyStoreError('restore', error);
      _setIfMounted(
        SignedOut(lastBaseUrl: parsed is BaseUrlOk ? parsed.key : null),
      );
    }
  }

  /// A bare token has no known age. Start its seven-day clock now instead of
  /// rotating immediately on the first launch after the upgrade.
  Future<StoredKey> _migrateLegacy(String instanceKey, StoredKey stored) async {
    if (!stored.legacy) return stored;
    final migrated = StoredKey(
      token: stored.token,
      keyId: stored.keyId,
      createdAt: _now(),
      expiresAt: stored.expiresAt,
    );
    try {
      await _keys.write(instanceKey, migrated);
    } on Object catch (error) {
      // Keeping the token is what matters. The next start tries again.
      _logKeyStoreError('migrate', error);
    }
    return migrated;
  }

  Future<void> _deleteOrphanedKeys() async {
    try {
      final all = await _keys.readAll();
      for (final instance in all.keys) {
        await _keys.delete(instance);
      }
    } on Object catch (error) {
      // Best effort. A key without its address is unreachable anyway, so a
      // failed cleanup must not change the outcome.
      _logKeyStoreError('orphan cleanup', error);
    }
  }

  void _logKeyStoreError(String operation, Object error) {
    final code = error is PlatformException ? ' (${error.code})' : '';
    debugPrint(
      'SessionController: keystore $operation failed: '
      '${error.runtimeType}$code',
    );
  }

  void _logRotationError(String operation, Object error) {
    final code = error is PlatformException ? ' (${error.code})' : '';
    debugPrint(
      'SessionController: key rotation $operation failed: '
      '${error.runtimeType}$code',
    );
  }

  void _setIfMounted(SessionState next) {
    if (ref.mounted) state = next;
  }

  /// Stores [token] for [baseUrl] and signs in.
  ///
  /// Clears any cached answers first, so a previous account on the same server
  /// cannot flash on screen for the new one.
  ///
  /// [keyId] and [expiresAt] are stored when the server reported them, so a
  /// later rotation can revoke this key and knows when it dies.
  Future<void> signIn({
    required Uri baseUrl,
    required String token,
    String? keyId,
    DateTime? expiresAt,
  }) async {
    final key = baseUrl.toString();
    _generation++;
    _rotatingToken = null;
    await _prefs.clearCachedData();
    await _keys.write(
      key,
      StoredKey(
        token: token,
        keyId: keyId,
        createdAt: _now(),
        expiresAt: expiresAt,
      ),
    );
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

  /// Replaces the key when it is seven days old (PRD S1 AC9).
  ///
  /// Safe to call often: an in-flight rotation is reused, and anything younger
  /// than [rotationAge] does nothing. A failed mint, store or revoke never
  /// signs the user out; the old key keeps working until it expires.
  Future<void> rotateIfNeeded() {
    final running = _rotation;
    if (running != null) return running;
    final future = _rotateIfNeeded();
    _rotation = future;
    return future.whenComplete(() {
      if (identical(_rotation, future)) _rotation = null;
    });
  }

  Future<void> _rotateIfNeeded() async {
    final current = state;
    if (current is! SignedIn || current.isDemo) return;
    final instanceKey = current.baseUrl.toString();
    final now = _now();
    final keys = _keys;
    final rotation = ref.read(keyRotationRepositoryProvider);
    final keyName = ref.read(keyNameProvider);

    final StoredKey? stored;
    try {
      stored = await keys.read(instanceKey);
    } on Object catch (error) {
      _logKeyStoreError('rotation read', error);
      return;
    }
    if (!ref.mounted ||
        stored == null ||
        !stored.isUsable ||
        stored.token != current.token) {
      return;
    }

    if (stored.isExpiredAt(now)) {
      // The key cannot authenticate, so do not spend a request on it. G3.
      await _clear(SignedOutReason.expired);
      return;
    }
    if (!stored.ageAtLeast(rotationAge, now)) return;

    final generation = _generation;
    final oldToken = stored.token;

    final BoardKey minted;
    try {
      minted = await rotation.mintKey(
        baseUrl: current.baseUrl,
        token: oldToken,
        keyName: keyName,
      );
    } on Unauthorized {
      if (_generation == generation) await handleUnauthorized(oldToken);
      return;
    } on Object catch (error) {
      // Offline or server error: keep the old key, as PRD S1 AC9 requires.
      _logRotationError('mint', error);
      return;
    }

    if (!ref.mounted || _generation != generation) {
      // Signed out (or signed in again) while the mint was in flight. Do not
      // store the replacement; discard it instead.
      await _revokeUnused(rotation, current.baseUrl, minted.token);
      return;
    }
    if (minted.token.isEmpty || minted.expiresAt == null) {
      // The app never stores a key without an explicit expiry.
      await _revokeUnused(rotation, current.baseUrl, minted.token);
      return;
    }

    final next = StoredKey(
      token: minted.token,
      keyId: minted.id,
      createdAt: now,
      expiresAt: minted.expiresAt,
    );

    _rotatingToken = next.token;
    try {
      await keys.write(instanceKey, next);
    } on Object catch (error) {
      _rotatingToken = null;
      _logKeyStoreError('rotation write', error);
      // The old key is still stored and valid. Discard the new one.
      await _revokeUnused(rotation, current.baseUrl, next.token);
      return;
    }

    if (!ref.mounted ||
        _generation != generation ||
        state is! SignedIn ||
        (state as SignedIn).token != oldToken) {
      // Sign-out (or a new sign-in) happened while the new key was written.
      // Leave no credential behind and discard the key the server minted.
      _rotatingToken = null;
      await _deleteIfStored(keys, instanceKey, next.token);
      await _revokeUnused(rotation, current.baseUrl, next.token);
      return;
    }

    state = SignedIn(baseUrl: current.baseUrl, token: next.token);
    _rotatingToken = null;

    // The new key is stored and in use. Only now delete the old one.
    final oldId = stored.keyId;
    if (oldId == null) return;
    try {
      await rotation.revokeKeyById(
        baseUrl: current.baseUrl,
        token: next.token,
        keyId: oldId,
      );
    } on Object catch (error) {
      // Best effort. The old key still expires on its own.
      _logRotationError('revoke old', error);
    }
  }

  Future<void> _deleteIfStored(
    KeyStore keys,
    String instanceKey,
    String token,
  ) async {
    try {
      final stored = await keys.read(instanceKey);
      if (stored?.token == token) await keys.delete(instanceKey);
    } on Object catch (error) {
      _logKeyStoreError('rotation cleanup', error);
    }
  }

  Future<void> _revokeUnused(
    AuthRepository rotation,
    Uri baseUrl,
    String token,
  ) async {
    if (token.isEmpty) return;
    try {
      await rotation.revokeKey(baseUrl: baseUrl, token: token);
    } on Object catch (error) {
      // Best effort: the key expires on its own.
      _logRotationError('revoke unused', error);
    }
  }

  Future<void> _clear(SignedOutReason reason) async {
    final current = state;
    if (current is! SignedIn || current.isDemo) return;
    _generation++;
    final baseKey = current.baseUrl.toString();
    final token = current.token;
    final rotating = _rotatingToken;
    // Switch state first so late responses and a second 401 do nothing.
    state = SignedOut(lastBaseUrl: baseKey, reason: reason);
    await _prefs.clearCachedData();
    if (state is SignedIn) return;
    try {
      // A very fast sign-in on the same URL may already have written a new
      // key. Only delete the key this sign-out belongs to (or the one a
      // rotation is in the middle of writing).
      final stored = await _keys.read(baseKey);
      if (stored != null &&
          (stored.token == token || stored.token == rotating)) {
        await _keys.delete(baseKey);
      }
    } on Object catch (error) {
      // The user is already signed out. A keystore error must not surface as
      // an unhandled error in the sign-out sheet.
      _logKeyStoreError('sign out', error);
    }
  }
}

/// The session.
final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
