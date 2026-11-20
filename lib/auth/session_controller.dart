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
///
/// A sign-out that cannot prove the device key was deleted is recorded as
/// incomplete. The key is not restored at the next start and the removal is
/// retried; it is never revoked while it may still be stored.
class SessionController extends Notifier<SessionState> {
  /// How old a key may be before the app replaces it.
  static const rotationAge = Duration(days: 7);

  int _generation = 0;
  String? _rotatingToken;
  Future<void>? _rotation;

  /// True between [beginSignOut] and the end of [signOut]. An explicit sign-out
  /// revokes the key on the server first, and no rotation may start or settle
  /// while that request is on the wire.
  bool _signingOut = false;

  /// One write queue per server address. Secure-storage read-modify-write
  /// sequences (sign-in, sign-out, the rotation swap) must not interleave for
  /// the same entry, or a delayed rotation write can delete a newer sign-in's
  /// key. Network calls stay outside the queue.
  final Map<String, Completer<void>> _storeTails = {};

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
      if (await _keys.isSignOutPending(parsed.key)) {
        // The user asked to remove this key and the last sign-out could not
        // prove it was deleted. Never present it as a session again. Retry the
        // removal; a success clears the marker but still shows S1, because the
        // key is the one the user wanted gone.
        final removed = await _deleteStoredKey(parsed.key);
        if (removed) await _clearSignOutMarker(parsed.key);
        _setIfMounted(
          SignedOut(
            lastBaseUrl: parsed.key,
            reason: SignedOutReason.userRequested,
            cleanupPending: !removed,
          ),
        );
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
      origin: stored.origin,
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

  /// Runs [action] after every earlier queued store mutation for [instanceKey].
  ///
  /// The queue always advances, even when an action throws, so one failed
  /// write cannot strand later sign-ins or sign-outs.
  Future<T> _serializeStore<T>(
    String instanceKey,
    Future<T> Function() action,
  ) {
    final previous = _storeTails[instanceKey]?.future ?? Future<void>.value();
    final done = Completer<void>();
    _storeTails[instanceKey] = done;
    Future<T> run() async {
      try {
        return await action();
      } finally {
        done.complete();
        if (identical(_storeTails[instanceKey], done)) {
          _storeTails.remove(instanceKey);
        }
      }
    }

    return previous.then((_) => run());
  }

  /// Stores [token] for [baseUrl] and signs in.
  ///
  /// Clears any cached answers first, so a previous account on the same server
  /// cannot flash on screen for the new one.
  ///
  /// [keyId] and [expiresAt] are stored when the server reported them, so a
  /// later rotation can revoke this key and knows when it dies.
  ///
  /// [origin] records whether Paperplane minted the key or the user pasted it.
  /// Only a minted key is revoked after a rotation.
  Future<void> signIn({
    required Uri baseUrl,
    required String token,
    String? keyId,
    DateTime? expiresAt,
    KeyOrigin origin = KeyOrigin.minted,
  }) async {
    final key = baseUrl.toString();
    _generation++;
    _rotatingToken = null;
    _signingOut = false;
    await _prefs.clearCachedData();
    await _serializeStore(key, () async {
      await _keys.write(
        key,
        StoredKey(
          token: token,
          keyId: keyId,
          createdAt: _now(),
          expiresAt: expiresAt,
          origin: origin,
        ),
      );
      // A completed sign-in is the recovery action for an incomplete sign-out
      // on this server: the new key has replaced the old entry.
      await _keys.clearSignOutPending(key);
    });
    await _prefs.setLastBaseUrl(key);
    state = SignedIn(baseUrl: baseUrl, token: token);
  }

  /// Marks an explicit sign-out as started, before the caller revokes the key
  /// on the server. [signOut] must follow.
  ///
  /// The pending sign-out is recorded in the secure store first. If that write
  /// fails, this throws and the caller must abort the disconnect without
  /// revoking the server key: the session is still valid and must not be
  /// reported as signed out.
  ///
  /// Bumping the generation here makes an in-flight rotation discard and revoke
  /// a key it minted while the revoke request is on the wire. Without this, a
  /// rotation that completes during that request becomes the session, and the
  /// following [signOut] deletes it locally without revoking it, leaving a live
  /// key on the server (S1 AC10).
  Future<void> beginSignOut() async {
    final current = state;
    if (current is! SignedIn || current.isDemo) return;
    final instanceKey = current.baseUrl.toString();
    // Stop new rotations and make an in-flight one discard its replacement
    // before the marker write can yield.
    _signingOut = true;
    _generation++;
    try {
      await _keys.markSignOutPending(instanceKey);
    } on Object {
      // No durable record. The caller aborts without revoking, so allow
      // rotations again; the swapped generation only discards in-flight work.
      _signingOut = false;
      rethrow;
    }
  }

  /// Deletes the stored key and shows S1. Revoking the key on the server is
  /// the caller's job and happens before this.
  ///
  /// Returns true when the store proves the key is gone. When it returns false
  /// the state is [SignedOut] with `cleanupPending`, the key is never restored
  /// and the removal is retried at the next start.
  Future<bool> signOut() => _clear(SignedOutReason.userRequested);

  /// A call returned 401: forget the key and show S1 (G3).
  ///
  /// [token] is the key the failed request carried. When it no longer matches
  /// the current session, the 401 belongs to a key the user already replaced
  /// (for example a request that was in flight during sign-out and sign-in)
  /// and must not sign out the new session.
  ///
  /// Safe to call many times; only the first for the current key has an
  /// effect.
  Future<void> handleUnauthorized([String? token]) async {
    final current = state;
    if (token != null &&
        current is SignedIn &&
        !current.isDemo &&
        current.token != token) {
      return;
    }
    await _clear(SignedOutReason.expired);
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
    if (_signingOut) return;
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
    final swap = await _serializeStore(
      instanceKey,
      () => _swapStoredKey(
        keys: keys,
        instanceKey: instanceKey,
        generation: generation,
        oldToken: oldToken,
        next: next,
      ),
    );

    switch (swap) {
      case _SwapOutcome.lost:
        // A sign-out, sign-in or another rotation owns the entry now. Never
        // overwrite it; only remove our own key if it is (unexpectedly) there.
        // Revoke it only once the store confirms it is gone.
        if (!await _deleteIfStored(instanceKey, next.token)) return;
        _rotatingToken = null;
        await _revokeUnused(rotation, current.baseUrl, next.token);
        return;
      case _SwapOutcome.oldKept:
        _rotatingToken = null;
        // The old key is still stored and valid. Discard the new one.
        await _revokeUnused(rotation, current.baseUrl, next.token);
        return;
      case _SwapOutcome.unknown:
        // The write may have committed before it reported an error, so the new
        // key may be the one in use. Revoking it could destroy the session, so
        // leave it to expire on its own. Keep it as the rotating token so a
        // following sign-out can still try to remove it if it is stored.
        // See SECURITY.md.
        _logRotationError(
          'write reconcile',
          StateError('secure store unreadable'),
        );
        return;
      case _SwapOutcome.wrote:
        break;
    }

    if (!ref.mounted ||
        _generation != generation ||
        state is! SignedIn ||
        (state as SignedIn).token != oldToken) {
      // Sign-out (or a new sign-in) happened while the new key was written.
      // Remove the minted key before revoking it. If the store cannot prove
      // the removal, keep the key valid and leave _rotatingToken set so a
      // following sign-out retries: a stored key must never be revoked.
      if (!await _deleteIfStored(instanceKey, next.token)) return;
      _rotatingToken = null;
      await _revokeUnused(rotation, current.baseUrl, next.token);
      return;
    }

    state = SignedIn(baseUrl: current.baseUrl, token: next.token);
    _rotatingToken = null;

    // The new key is stored and in use. Only now revoke the old one, and only
    // when Paperplane created it: a pasted key may be in use elsewhere.
    if (stored.origin != KeyOrigin.minted) return;
    final oldId = stored.keyId;
    if (oldId == null) {
      // No server id was recorded (legacy migration or a server that did not
      // return one), but the app still holds the old secret, so retire the old
      // key by revoking it with the new one.
      try {
        await rotation.revokeKey(baseUrl: current.baseUrl, token: oldToken);
      } on Object catch (error) {
        // Best effort. The old key still expires on its own.
        _logRotationError('revoke old', error);
      }
      return;
    }
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

  /// Proves the entry is still [oldToken] and writes [next] in the same
  /// serialized step, so a sign-out or sign-in cannot interleave.
  Future<_SwapOutcome> _swapStoredKey({
    required KeyStore keys,
    required String instanceKey,
    required int generation,
    required String oldToken,
    required StoredKey next,
  }) async {
    if (!ref.mounted || _generation != generation) return _SwapOutcome.lost;

    final StoredKey? current;
    try {
      current = await keys.read(instanceKey);
    } on Object catch (error) {
      // The write never ran, so the old key is still the only one stored.
      _logKeyStoreError('rotation write check', error);
      return _SwapOutcome.oldKept;
    }
    if (current?.token != oldToken) return _SwapOutcome.lost;

    try {
      await keys.write(instanceKey, next);
      return _SwapOutcome.wrote;
    } on Object catch (error) {
      _logKeyStoreError('rotation write', error);
      // A failed Future does not prove the old value remains: some platforms
      // commit before reporting an error. Read back before revoking.
      final StoredKey? after;
      try {
        after = await keys.read(instanceKey);
      } on Object catch (readError) {
        _logKeyStoreError('rotation write reconcile', readError);
        return _SwapOutcome.unknown;
      }
      if (after?.token == next.token) return _SwapOutcome.wrote;
      if (after?.token == oldToken) return _SwapOutcome.oldKept;
      return _SwapOutcome.unknown;
    }
  }

  /// Removes [token] from the entry when it is still the stored key.
  ///
  /// Returns true when the entry is proven not to hold [token] afterwards:
  /// deleted, already absent, or replaced by another operation. Returns false
  /// when the store cannot be read, so the caller must not revoke a key that
  /// may still be stored. A delete can fail after the platform committed it,
  /// so the entry is read back before giving up.
  Future<bool> _deleteIfStored(String instanceKey, String token) =>
      _serializeStore(instanceKey, () async {
        try {
          final stored = await _keys.read(instanceKey);
          if (stored?.token != token) return true;
          await _keys.delete(instanceKey);
          return true;
        } on Object catch (error) {
          _logKeyStoreError('rotation cleanup', error);
          try {
            final after = await _keys.read(instanceKey);
            return after?.token != token;
          } on Object catch (readError) {
            _logKeyStoreError('rotation cleanup reconcile', readError);
            return false;
          }
        }
      });

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

  /// Deletes whatever is stored for [instanceKey] and reports whether the
  /// entry is proven gone. Used to finish an incomplete sign-out at start-up.
  Future<bool> _deleteStoredKey(String instanceKey) =>
      _serializeStore(instanceKey, () async {
        try {
          await _keys.delete(instanceKey);
          return true;
        } on Object catch (error) {
          _logKeyStoreError('pending sign-out cleanup', error);
          // A delete can fail after the platform committed it, so read back.
          try {
            return await _keys.read(instanceKey) == null;
          } on Object catch (readError) {
            _logKeyStoreError('pending sign-out cleanup reconcile', readError);
            return false;
          }
        }
      });

  /// Deletes the entry when it still holds [token] or [rotating].
  ///
  /// Returns true when the entry is proven not to hold either: deleted,
  /// already absent, or replaced by another operation. Returns false when the
  /// store cannot be read, so the caller must not revoke a key that may still
  /// be stored.
  Future<bool> _removeIfOurs(
    String instanceKey,
    String token,
    String? rotating,
  ) async {
    try {
      final stored = await _keys.read(instanceKey);
      if (stored == null) return true;
      if (stored.token != token && stored.token != rotating) {
        // A very fast sign-in on the same URL may already have written a new
        // key. Only delete the key this sign-out belongs to (or the one a
        // rotation was in the middle of writing when this began).
        return true;
      }
      await _keys.delete(instanceKey);
      return true;
    } on Object catch (error) {
      // The user is already signed out. A keystore error must not surface as
      // an unhandled error in the sign-out sheet.
      _logKeyStoreError('sign out', error);
      // A delete can fail after the platform committed it, so read back.
      try {
        final after = await _keys.read(instanceKey);
        return after == null ||
            (after.token != token && after.token != rotating);
      } on Object catch (readError) {
        _logKeyStoreError('sign out reconcile', readError);
        return false;
      }
    }
  }

  Future<bool> _clear(SignedOutReason reason) async {
    final current = state;
    if (current is! SignedIn || current.isDemo) return true;
    _generation++;
    final baseKey = current.baseUrl.toString();
    final token = current.token!;
    final rotating = _rotatingToken;
    // Record the intent in the secure store before changing state or doing any
    // other asynchronous work. If it cannot be recorded, do not report an
    // explicit sign-out: the key must never be silently restored later.
    final marked = await _ensureSignOutMarked(baseKey);
    if (!marked && reason == SignedOutReason.userRequested) return false;
    // A very fast sign-in may have replaced the session while the marker was
    // written. Keep it: its write already replaced the old entry and cleared
    // the marker for this server.
    final replaced = state;
    if (replaced is SignedIn && replaced.token != token) return true;
    // Switch state first so late responses and a second 401 do nothing.
    state = SignedOut(lastBaseUrl: baseKey, reason: reason);
    _signingOut = false;
    await _prefs.clearCachedData();
    if (state is SignedIn) return true;
    return await _serializeStore(baseKey, () async {
      final removed = await _removeIfOurs(baseKey, token, rotating);
      if (removed) {
        await _clearSignOutMarker(baseKey);
        return true;
      }
      // A sign-in may have won while the delete failed. Never overwrite it.
      final now = state;
      if (now is SignedOut && now.lastBaseUrl == baseKey) {
        state = SignedOut(
          lastBaseUrl: baseKey,
          reason: reason,
          cleanupPending: true,
        );
      }
      return false;
    });
  }

  /// Makes sure the secure store holds proof that this sign-out must finish.
  ///
  /// Reads first so a marker written by [beginSignOut] is not written again.
  /// Returns false when it cannot be recorded.
  Future<bool> _ensureSignOutMarked(String instanceKey) async {
    try {
      if (await _keys.isSignOutPending(instanceKey)) return true;
    } on Object catch (error) {
      _logKeyStoreError('sign-out marker read', error);
    }
    try {
      await _keys.markSignOutPending(instanceKey);
      return true;
    } on Object catch (error) {
      _logKeyStoreError('sign-out marker', error);
      return false;
    }
  }

  /// Removes the pending marker. The key is already gone, so a failure only
  /// means the next start retries a harmless no-op.
  Future<void> _clearSignOutMarker(String instanceKey) async {
    try {
      await _keys.clearSignOutPending(instanceKey);
    } on Object catch (error) {
      _logKeyStoreError('sign-out marker clear', error);
    }
  }
}

/// What a serialized rotation write did to the secure entry.
enum _SwapOutcome {
  /// The replacement is stored.
  wrote,

  /// Another operation owns the entry; nothing was written.
  lost,

  /// The write failed and the old key is still stored.
  oldKept,

  /// The write failed and the entry could not be read back, so it is unclear
  /// which key, if any, is stored.
  unknown,
}

/// The session.
final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
