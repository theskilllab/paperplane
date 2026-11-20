import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/json.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/auth/stored_key.dart';
import 'package:paperplane/data/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_adapter.dart';
import '../support/throwing_key_store.dart';

const _instance = 'https://paperclip.example.test';
final _now = DateTime.utc(2026, 11, 20, 12);
const _thirtyDays = Duration(days: 30);

StoredKey _record({
  String token = 'old-key',
  String? keyId = 'key-old',
  Duration age = Duration.zero,
  DateTime? expiresAt,
  KeyOrigin origin = KeyOrigin.minted,
  String sessionId = 'session-old',
}) => StoredKey(
  token: token,
  keyId: keyId,
  createdAt: _now.subtract(age),
  expiresAt: expiresAt,
  origin: origin,
  sessionId: sessionId,
);

Future<ProviderContainer> _container({
  required KeyStore keys,
  required FakeAdapter adapter,
  AppPrefs? prefs,
}) async {
  if (prefs == null) {
    SharedPreferences.setMockInitialValues({'last_base_url': _instance});
  }
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appPrefsProvider.overrideWithValue(
        prefs ?? AppPrefs(await SharedPreferences.getInstance()),
      ),
      keyStoreProvider.overrideWithValue(keys),
      appEnvProvider.overrideWith(() => AppEnvController(const AppEnv())),
      clockProvider.overrideWithValue(() => _now),
      keyNameProvider.overrideWithValue('Paperplane (Test Phone)'),
      keyRotationRepositoryProvider.overrideWithValue(
        HttpAuthRepository(adapter: adapter, now: () => _now),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(sessionControllerProvider, (_, _) {});
  return container;
}

Future<SessionState> _settled(ProviderContainer c) =>
    pumpEventQueue().then((_) => c.read(sessionControllerProvider));

Map<String, Object?> _minted({
  String token = 'new-key',
  String? id = 'key-new',
  DateTime? expiresAt,
}) => {
  'id': id,
  'name': 'Paperplane (Test Phone)',
  'token': token,
  'expiresAt': (expiresAt ?? _now.add(_thirtyDays)).toIso8601String(),
};

FakeAdapter _happyAdapter() => FakeAdapter((o) async {
  return switch ('${o.method} ${o.path}') {
    'POST /board-api-keys' => jsonBody(_minted(), status: 201),
    'DELETE /board-api-keys/key-old' => jsonBody(<String, Object?>{}),
    'POST /cli-auth/revoke-current' => jsonBody(<String, Object?>{}),
    _ => fail('unexpected ${o.method} ${o.path}'),
  };
});

String _auth(RequestOptions request) =>
    asMap(request.headers)['Authorization'] as String? ?? '';

void main() {
  test('replaces a seven-day-old key and revokes the old one last', () async {
    final keys = InMemoryKeyStore();
    await keys.write(_instance, _record());
    final adapter = _happyAdapter();
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);

    // The key was fresh at restore; make it old, as seven days of use would.
    await keys.write(_instance, _record(age: const Duration(days: 8)));
    await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

    final state = c.read(sessionControllerProvider) as SignedIn;
    expect(state.token, 'new-key');
    final stored = await keys.read(_instance);
    expect(stored?.token, 'new-key');
    expect(stored?.keyId, 'key-new');
    expect(stored?.createdAt, _now);
    expect(stored?.expiresAt, _now.add(_thirtyDays));

    final mint = adapter.requests.firstWhere(
      (r) => r.method == 'POST' && r.path == '/board-api-keys',
    );
    expect(_auth(mint), 'Bearer old-key');
    expect(mint.headers['Origin'], _instance);
    expect(mint.data, {
      'name': 'Paperplane (Test Phone)',
      'expiresAt': _now.add(_thirtyDays).toIso8601String(),
    });

    final revoke = adapter.requests.singleWhere((r) => r.method == 'DELETE');
    expect(revoke.path, '/board-api-keys/key-old');
    expect(_auth(revoke), 'Bearer new-key');
    expect(revoke.headers['Origin'], _instance);
    expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
      'POST /board-api-keys',
      'DELETE /board-api-keys/key-old',
    ], reason: 'the old key is deleted only after the new one is stored');
  });

  test('a key younger than seven days is left alone', () async {
    final keys = InMemoryKeyStore();
    await keys.write(_instance, _record(age: const Duration(days: 6)));
    final adapter = FakeAdapter((o) async {
      fail('no request expected, got ${o.method} ${o.path}');
    });
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

    expect(adapter.requests, isEmpty);
    expect((await keys.read(_instance))?.token, 'old-key');
    expect((c.read(sessionControllerProvider) as SignedIn).token, 'old-key');
  });

  test(
    'a legacy bare token gets a start date and is not rotated at once',
    () async {
      final keys = InMemoryKeyStore();
      await keys.write(
        _instance,
        StoredKey(
          token: 'old-key',
          createdAt: DateTime.utc(2000),
          legacy: true,
        ),
      );
      final adapter = FakeAdapter((o) async {
        fail('no request expected, got ${o.method} ${o.path}');
      });
      final c = await _container(keys: keys, adapter: adapter);
      final state = await _settled(c) as SignedIn;

      expect(state.token, 'old-key');
      final stored = await keys.read(_instance);
      expect(stored?.legacy, isFalse);
      expect(stored?.createdAt, _now);
      expect(adapter.requests, isEmpty);
    },
  );

  test('an offline mint keeps the old key working', () async {
    final keys = InMemoryKeyStore();
    await keys.write(_instance, _record());
    final adapter = FakeAdapter((o) async {
      throw DioException.connectionError(
        requestOptions: o,
        reason: 'offline',
        error: const SocketException('no route'),
      );
    });
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await keys.write(_instance, _record(age: const Duration(days: 8)));
    await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

    expect((await keys.read(_instance))?.token, 'old-key');
    final state = c.read(sessionControllerProvider) as SignedIn;
    expect(state.token, 'old-key');
  });

  test('a mint failure keeps the old key working', () async {
    final keys = InMemoryKeyStore();
    await keys.write(_instance, _record());
    final adapter = FakeAdapter((o) async => jsonBody(null, status: 500));
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await keys.write(_instance, _record(age: const Duration(days: 8)));
    await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

    expect((await keys.read(_instance))?.token, 'old-key');
    expect((c.read(sessionControllerProvider) as SignedIn).token, 'old-key');
    expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
      'POST /board-api-keys',
    ]);
  });

  test('a failed store keeps the old key and revokes the new one', () async {
    final keys = ThrowingKeyStore(
      values: {_instance: _record(age: const Duration(days: 8))},
    )..failWrite = true;
    final adapter = FakeAdapter((o) async {
      return switch ('${o.method} ${o.path}') {
        'POST /board-api-keys' => jsonBody(_minted(), status: 201),
        'POST /cli-auth/revoke-current' => jsonBody(<String, Object?>{}),
        _ => fail('unexpected ${o.method} ${o.path}'),
      };
    });
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

    expect((await keys.read(_instance))?.token, 'old-key');
    expect((c.read(sessionControllerProvider) as SignedIn).token, 'old-key');
    final revokes = adapter.requests.where(
      (r) => r.path == '/cli-auth/revoke-current',
    );
    expect(revokes, isNotEmpty);
    expect(revokes.every((r) => _auth(r) == 'Bearer new-key'), isTrue);
  });

  test('a minted key without an explicit expiry is never stored', () async {
    final keys = InMemoryKeyStore();
    await keys.write(_instance, _record());
    final adapter = FakeAdapter((o) async {
      return switch ('${o.method} ${o.path}') {
        'POST /board-api-keys' => jsonBody({
          'id': 'key-new',
          'token': 'new-key',
        }, status: 201),
        'POST /cli-auth/revoke-current' => jsonBody(<String, Object?>{}),
        _ => fail('unexpected ${o.method} ${o.path}'),
      };
    });
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await keys.write(_instance, _record(age: const Duration(days: 8)));
    await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

    expect((await keys.read(_instance))?.token, 'old-key');
    expect((c.read(sessionControllerProvider) as SignedIn).token, 'old-key');
    final revokeNew = adapter.requests.singleWhere(
      (r) => r.path == '/cli-auth/revoke-current',
    );
    expect(_auth(revokeNew), 'Bearer new-key');
  });

  test(
    'an already-expired key signs out without a network call (G3)',
    () async {
      final keys = InMemoryKeyStore();
      await keys.write(
        _instance,
        _record(
          age: const Duration(days: 8),
          expiresAt: _now.subtract(const Duration(minutes: 1)),
        ),
      );
      final adapter = FakeAdapter((o) async {
        fail('no request expected, got ${o.method} ${o.path}');
      });
      final c = await _container(keys: keys, adapter: adapter);
      await _settled(c);
      await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

      final state = c.read(sessionControllerProvider) as SignedOut;
      expect(state.reason, SignedOutReason.expired);
      expect(state.lastBaseUrl, _instance);
      expect(await keys.read(_instance), isNull);
      expect(adapter.requests, isEmpty);
    },
  );

  test('a 401 on mint signs out and deletes the key (G3)', () async {
    final keys = InMemoryKeyStore();
    await keys.write(_instance, _record());
    final adapter = FakeAdapter((o) async => jsonBody(null, status: 401));
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await keys.write(_instance, _record(age: const Duration(days: 8)));
    await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

    final state = c.read(sessionControllerProvider) as SignedOut;
    expect(state.reason, SignedOutReason.expired);
    expect(await keys.read(_instance), isNull);
  });

  test('concurrent calls share one in-flight rotation', () async {
    final keys = InMemoryKeyStore();
    await keys.write(_instance, _record());
    final started = Completer<void>();
    final release = Completer<void>();
    var mints = 0;
    final adapter = FakeAdapter((o) async {
      switch ('${o.method} ${o.path}') {
        case 'POST /board-api-keys':
          mints++;
          started.complete();
          await release.future;
          return jsonBody(_minted(), status: 201);
        case 'DELETE /board-api-keys/key-old':
          return jsonBody(<String, Object?>{});
        default:
          fail('unexpected ${o.method} ${o.path}');
      }
    });
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await keys.write(_instance, _record(age: const Duration(days: 8)));

    final notifier = c.read(sessionControllerProvider.notifier);
    final first = notifier.rotateIfNeeded();
    final second = notifier.rotateIfNeeded();
    await started.future;
    release.complete();
    await Future.wait([first, second]);

    expect(mints, 1);
    expect((await keys.read(_instance))?.token, 'new-key');
  });

  test('sign-out during mint leaves no key behind', () async {
    final keys = InMemoryKeyStore();
    await keys.write(_instance, _record());
    final started = Completer<void>();
    final release = Completer<void>();
    final adapter = FakeAdapter((o) async {
      switch ('${o.method} ${o.path}') {
        case 'POST /board-api-keys':
          started.complete();
          await release.future;
          return jsonBody(_minted(), status: 201);
        case 'POST /cli-auth/revoke-current':
          return jsonBody(<String, Object?>{});
        default:
          fail('unexpected ${o.method} ${o.path}');
      }
    });
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await keys.write(_instance, _record(age: const Duration(days: 8)));

    final notifier = c.read(sessionControllerProvider.notifier);
    final rotation = notifier.rotateIfNeeded();
    await started.future;
    await notifier.signOut();
    release.complete();
    await rotation;

    expect(c.read(sessionControllerProvider), isA<SignedOut>());
    expect(await keys.read(_instance), isNull);
    final revokeNew = adapter.requests.singleWhere(
      (r) => r.path == '/cli-auth/revoke-current',
    );
    expect(_auth(revokeNew), 'Bearer new-key');
  });

  test('a sign-out that starts before the rotation write settles revokes the '
      'minted key', () async {
    final keys = _GatedKeyStore();
    await keys.write(_instance, _record());
    final adapter = _happyAdapter();
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await keys.write(_instance, _record(age: const Duration(days: 8)));

    keys.gateWrites = true;
    final notifier = c.read(sessionControllerProvider.notifier);
    final rotation = notifier.rotateIfNeeded();
    await keys.writeStarted.future;

    // The user confirms sign-out. The server revoke is on the wire before
    // the local session clears, so the rotation is still in flight here.
    await notifier.beginSignOut();
    keys.releaseWrite.complete();
    await rotation;

    expect(
      (c.read(sessionControllerProvider) as SignedIn).token,
      'old-key',
      reason: 'the rotation must not become the session during sign-out',
    );
    expect(await keys.read(_instance), isNull);
    final revoked = adapter.requests
        .where((r) => r.path == '/cli-auth/revoke-current')
        .map(_auth);
    expect(
      revoked,
      contains('Bearer new-key'),
      reason: 'the replacement must not stay valid after sign-out',
    );
    expect(
      adapter.requests.where((r) => r.method == 'DELETE'),
      isEmpty,
      reason: 'the old key is retired by the sign-out revoke, not rotation',
    );

    await notifier.signOut();

    expect(c.read(sessionControllerProvider), isA<SignedOut>());
    expect(await keys.read(_instance), isNull);
  });

  test('sign-out while the new key is being stored leaves no key', () async {
    final keys = _GatedKeyStore();
    await keys.write(_instance, _record());
    final adapter = _happyAdapter();
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await keys.write(_instance, _record(age: const Duration(days: 8)));

    keys.gateWrites = true;
    final notifier = c.read(sessionControllerProvider.notifier);
    final rotation = notifier.rotateIfNeeded();
    await keys.writeStarted.future;
    final signOut = notifier.signOut();
    keys.releaseWrite.complete();
    await signOut;
    await rotation;

    expect(c.read(sessionControllerProvider), isA<SignedOut>());
    expect(await keys.read(_instance), isNull);
    final paths = adapter.requests.map((r) => '${r.method} ${r.path}');
    expect(paths, contains('POST /board-api-keys'));
    expect(
      adapter.requests.where((r) => r.method == 'DELETE'),
      isEmpty,
      reason: 'the old key is not deleted when the swap did not settle',
    );
    final revokedNew = adapter.requests.singleWhere(
      (r) => r.path == '/cli-auth/revoke-current',
    );
    expect(
      _auth(revokedNew),
      'Bearer new-key',
      reason: 'the minted key is discarded after the sign-out',
    );
  });

  test('an abandoned rotation whose cleanup delete fails keeps the replacement '
      'stored and does not revoke it', () async {
    final keys = _GatedKeyStore()..failDelete = true;
    await keys.write(_instance, _record());
    final adapter = _happyAdapter();
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await keys.write(_instance, _record(age: const Duration(days: 8)));

    keys.gateWrites = true;
    final notifier = c.read(sessionControllerProvider.notifier);
    final rotation = notifier.rotateIfNeeded();
    await keys.writeStarted.future;

    await notifier.beginSignOut();
    keys.releaseWrite.complete();
    await rotation;

    // The write committed, but the cleanup delete failed. Revoking now would
    // leave a stored key that the server rejects as the user's session.
    expect((await keys.read(_instance))?.token, 'new-key');
    expect(
      adapter.requests
          .where((r) => r.path == '/cli-auth/revoke-current')
          .map(_auth),
      isNot(contains('Bearer new-key')),
      reason: 'a key that may still be stored must stay valid',
    );

    final removed = await notifier.signOut();

    expect(removed, isFalse);
    final state = c.read(sessionControllerProvider) as SignedOut;
    expect(state.reason, SignedOutReason.userRequested);
    expect(
      state.cleanupPending,
      isTrue,
      reason: 'the sign-out must be observable as incomplete',
    );
    expect(
      (await keys.read(_instance))?.token,
      'new-key',
      reason: 'the delete still fails, so the valid key is kept recoverable',
    );
    expect(
      await keys.signOutPendingSessions(_instance),
      contains('session-old'),
      reason: 'a restart must know not to restore this key',
    );
    expect(
      adapter.requests
          .where((r) => r.path == '/cli-auth/revoke-current')
          .map(_auth),
      isNot(contains('Bearer new-key')),
      reason: 'the following sign-out must not revoke the stored key either',
    );
  });

  test('an incomplete sign-out is not restored after a restart', () async {
    final keys = _GatedKeyStore()..failDelete = true;
    await keys.write(_instance, _record());
    final adapter = _happyAdapter();

    final first = await _container(keys: keys, adapter: adapter);
    await _settled(first);
    await keys.write(_instance, _record(age: const Duration(days: 8)));

    keys.gateWrites = true;
    final notifier = first.read(sessionControllerProvider.notifier);
    final rotation = notifier.rotateIfNeeded();
    await keys.writeStarted.future;
    await notifier.beginSignOut();
    keys.releaseWrite.complete();
    await rotation;
    keys.gateWrites = false;

    expect(await notifier.signOut(), isFalse);
    expect((await keys.read(_instance))?.token, 'new-key');
    expect(
      await keys.signOutPendingSessions(_instance),
      contains('session-old'),
    );

    // Cold start with fresh preferences: the durable marker lives in the
    // secure store, not in preferences. The key the user asked to remove must
    // not come back as a session.
    final noRequests = FakeAdapter((o) async {
      fail('no request expected, got ${o.method} ${o.path}');
    });
    final second = await _container(keys: keys, adapter: noRequests);
    final restarted = await _settled(second);
    expect(restarted, isA<SignedOut>());
    expect((restarted as SignedOut).reason, SignedOutReason.userRequested);
    expect(restarted.cleanupPending, isTrue);
    expect(restarted.lastBaseUrl, _instance);
    expect(
      await keys.signOutPendingSessions(_instance),
      contains('session-old'),
    );
    expect(noRequests.requests, isEmpty);

    // Once removal succeeds, the next start clears the pending state but still
    // does not restore the key the user asked to remove.
    keys.failDelete = false;
    final third = await _container(keys: keys, adapter: noRequests);
    final cleaned = await _settled(third);
    expect(cleaned, isA<SignedOut>());
    expect((cleaned as SignedOut).cleanupPending, isFalse);
    expect(await keys.read(_instance), isNull);
    expect(await keys.signOutPendingSessions(_instance), isEmpty);

    // Signing in again is the explicit recovery action.
    await third
        .read(sessionControllerProvider.notifier)
        .signIn(baseUrl: Uri.parse(_instance), token: 'session-b');
    expect(
      (third.read(sessionControllerProvider) as SignedIn).token,
      'session-b',
    );
    expect(await keys.signOutPendingSessions(_instance), isEmpty);
  });

  test(
    'a sign-in clears the pending marker so a restart keeps the new key',
    () async {
      final keys = ThrowingKeyStore(values: {_instance: _record()})
        ..failDelete = true;
      final first = await _container(keys: keys, adapter: _happyAdapter());
      await _settled(first);
      final notifier = first.read(sessionControllerProvider.notifier);

      // An incomplete sign-out leaves the marker and the old key stored.
      expect(await notifier.signOut(), isFalse);
      expect(
        await keys.signOutPendingSessions(_instance),
        contains('session-old'),
      );
      expect((await keys.read(_instance))?.token, 'old-key');

      // Sign in again while the marker is still set. The new key replaces the
      // entry, so the marker must be cleared.
      await notifier.signIn(baseUrl: Uri.parse(_instance), token: 'session-b');
      expect(await keys.signOutPendingSessions(_instance), isEmpty);
      expect((await keys.read(_instance))?.token, 'session-b');

      // A cold start must keep the new session, not treat the old marker as
      // permission to delete the replacement.
      final second = await _container(keys: keys, adapter: _happyAdapter());
      final restarted = await _settled(second);
      expect(restarted, isA<SignedIn>());
      expect((restarted as SignedIn).token, 'session-b');
      expect((await keys.read(_instance))?.token, 'session-b');
    },
  );

  test(
    'a marker write that commits then throws still starts the sign-out',
    () async {
      final keys = ThrowingKeyStore(values: {_instance: _record()})
        ..throwAfterMarkSignedOut = true;
      final first = await _container(keys: keys, adapter: _happyAdapter());
      await _settled(first);
      final notifier = first.read(sessionControllerProvider.notifier);

      await notifier.beginSignOut();
      expect(
        await keys.signOutPendingSessions(_instance),
        contains('session-old'),
      );
      expect(await notifier.signOut(), isTrue);
      expect(await keys.read(_instance), isNull);
      expect(await keys.signOutPendingSessions(_instance), isEmpty);
    },
  );

  test('a same-token re-sign-in survives a failed marker clear', () async {
    final keys = ThrowingKeyStore(values: {_instance: _record()})
      ..failDelete = true;
    final first = await _container(keys: keys, adapter: _happyAdapter());
    await _settled(first);
    final notifier = first.read(sessionControllerProvider.notifier);

    // Leave a pending sign-out for the old session.
    expect(await notifier.signOut(), isFalse);
    expect(
      await keys.signOutPendingSessions(_instance),
      contains('session-old'),
    );

    // Sign in again with the SAME token, but the marker clear fails. The
    // marker names the old write, not the secret, so it must not delete the
    // new session.
    keys
      ..failDelete = false
      ..failClearSignedOut = true;
    await notifier.signIn(baseUrl: Uri.parse(_instance), token: 'old-key');
    expect(
      await keys.signOutPendingSessions(_instance),
      contains('session-old'),
    );
    final reSignedIn = await keys.read(_instance);
    expect(reSignedIn?.token, 'old-key');
    expect(reSignedIn?.sessionId, isNot('session-old'));

    // Fresh start with the marker still present: the new incarnation is
    // restored instead of deleted.
    final second = await _container(keys: keys, adapter: _happyAdapter());
    final restarted = await _settled(second);
    expect(restarted, isA<SignedIn>());
    expect((restarted as SignedIn).token, 'old-key');
    expect((await keys.read(_instance))?.token, 'old-key');

    // A later start clears the stale marker now the store works again.
    keys.failClearSignedOut = false;
    final third = await _container(keys: keys, adapter: _happyAdapter());
    await _settled(third);
    expect(await keys.signOutPendingSessions(_instance), isEmpty);
  });

  test('an interrupted sign-out records its intent before cleanup', () async {
    final keys = ThrowingKeyStore(values: {_instance: _record()});
    final adapter = _happyAdapter();
    SharedPreferences.setMockInitialValues({'last_base_url': _instance});
    final prefs = _GatedPrefs(await SharedPreferences.getInstance());

    final first = await _container(keys: keys, adapter: adapter, prefs: prefs);
    await _settled(first);
    final notifier = first.read(sessionControllerProvider.notifier);

    // Do not await: the sign-out is interrupted inside the cache clear, before
    // the key-store delete runs.
    final signingOut = notifier.signOut();
    await prefs.clearStarted.future;

    // The durable intent is already written and the key is still stored, so a
    // process death here cannot lead to a restore of the key.
    expect(
      await keys.signOutPendingSessions(_instance),
      contains('session-old'),
    );
    expect((await keys.read(_instance))?.token, 'old-key');
    expect(first.read(sessionControllerProvider), isA<SignedOut>());

    // Restart with fresh preferences while the first sign-out is stuck. Only
    // the secure-store marker can prevent a restore.
    keys.failDelete = true;
    final noRequests = FakeAdapter((o) async {
      fail('no request expected, got ${o.method} ${o.path}');
    });
    final second = await _container(keys: keys, adapter: noRequests);
    final restarted = await _settled(second);
    expect(restarted, isA<SignedOut>());
    expect((restarted as SignedOut).cleanupPending, isTrue);
    expect((await keys.read(_instance))?.token, 'old-key');
    expect(noRequests.requests, isEmpty);

    prefs.releaseClear.complete();
    expect(await signingOut, isFalse);
  });

  test(
    'a sign-out whose intent cannot be recorded does not report success',
    () async {
      final keys = ThrowingKeyStore(values: {_instance: _record()})
        ..failMarkSignedOut = true;
      final adapter = _happyAdapter();
      final first = await _container(keys: keys, adapter: adapter);
      await _settled(first);
      final notifier = first.read(sessionControllerProvider.notifier);

      expect(await notifier.signOut(), isFalse);
      expect(first.read(sessionControllerProvider), isA<SignedIn>());
      expect(await keys.signOutPendingSessions(_instance), isEmpty);
      expect((await keys.read(_instance))?.token, 'old-key');
      expect(adapter.requests, isEmpty);

      // The sign-out never happened, so a restart with a working store still
      // restores the valid key.
      keys.failMarkSignedOut = false;
      final second = await _container(keys: keys, adapter: _happyAdapter());
      final restarted = await _settled(second);
      expect(restarted, isA<SignedIn>());
      expect((restarted as SignedIn).token, 'old-key');
      expect(await keys.signOutPendingSessions(_instance), isEmpty);
    },
  );

  test('beginSignOut throws when the sign-out cannot be recorded', () async {
    final keys = ThrowingKeyStore(values: {_instance: _record()})
      ..failMarkSignedOut = true;
    final first = await _container(keys: keys, adapter: _happyAdapter());
    await _settled(first);
    final notifier = first.read(sessionControllerProvider.notifier);

    await expectLater(notifier.beginSignOut(), throwsA(isA<StateError>()));
    expect(first.read(sessionControllerProvider), isA<SignedIn>());
    expect(await keys.signOutPendingSessions(_instance), isEmpty);
  });

  test(
    'sign-out then a same-server sign-in during a gated rotation write keeps '
    'the new session key',
    () async {
      final keys = _GatedKeyStore();
      await keys.write(_instance, _record());
      final adapter = FakeAdapter((o) async {
        return switch ('${o.method} ${o.path}') {
          'POST /board-api-keys' => jsonBody(
            _minted(token: 'rotated-key', id: 'key-rotated'),
            status: 201,
          ),
          'POST /cli-auth/revoke-current' => jsonBody(<String, Object?>{}),
          _ => fail('unexpected ${o.method} ${o.path}'),
        };
      });
      final c = await _container(keys: keys, adapter: adapter);
      await _settled(c);
      await keys.write(_instance, _record(age: const Duration(days: 8)));

      // Hold only the rotation's write. A real store does not run writes in
      // registration order, so the sign-in write below must not be able to
      // overtake it. Gate every write on a shared completer instead and the
      // test would pass without the serialization queue (review B4).
      keys.gateToken = 'rotated-key';
      keys.committedTokens.clear();
      final notifier = c.read(sessionControllerProvider.notifier);
      final rotation = notifier.rotateIfNeeded();
      await keys.writeStarted.future;

      // The rotation write is held open. Sign out and sign in again to the
      // same server with a different key (B) before the write can land. Let
      // both reach the store now: without the queue their writes would land
      // inside the held rotation step.
      final signOut = notifier.signOut();
      final signIn = notifier.signIn(
        baseUrl: Uri.parse(_instance),
        token: 'session-b',
        keyId: 'key-b',
      );
      await pumpEventQueue();
      keys.releaseWrite.complete();
      await Future.wait([signOut, rotation, signIn]);

      final state = c.read(sessionControllerProvider) as SignedIn;
      expect(state.token, 'session-b');
      final stored = await keys.read(_instance);
      expect(stored?.token, 'session-b', reason: 'the new sign-in key kept');
      expect(stored?.keyId, 'key-b');
      expect(keys.committedTokens, [
        'rotated-key',
        'session-b',
      ], reason: 'the sign-in write must not interleave inside the rotation');
      final revoked = adapter.requests
          .where((r) => r.path == '/cli-auth/revoke-current')
          .map(_auth);
      expect(
        revoked,
        contains('Bearer rotated-key'),
        reason: 'the minted replacement is revoked when it loses the swap',
      );
      expect(adapter.requests.where((r) => r.method == 'DELETE'), isEmpty);
    },
  );

  test(
    'a store that commits then reports an error keeps the new key',
    () async {
      final keys = ThrowingKeyStore(values: {_instance: _record()});
      final adapter = _happyAdapter();
      final c = await _container(keys: keys, adapter: adapter);
      await _settled(c);
      await keys.write(_instance, _record(age: const Duration(days: 8)));
      keys.throwAfterWrite = true;

      await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

      final stored = await keys.read(_instance);
      expect(
        stored?.token,
        'new-key',
        reason:
            'the committed write is the live key; revoking it would break it',
      );
      expect((c.read(sessionControllerProvider) as SignedIn).token, 'new-key');
      expect(
        adapter.requests.where((r) => r.path == '/cli-auth/revoke-current'),
        isEmpty,
        reason: 'the new key is in use and must not be revoked',
      );
      final revokeOld = adapter.requests.singleWhere(
        (r) => r.method == 'DELETE',
      );
      expect(revokeOld.path, '/board-api-keys/key-old');
    },
  );

  test(
    'an unreadable store after a failed write does not revoke the new key',
    () async {
      final keys = ThrowingKeyStore(values: {_instance: _record()})
        ..failReadAfterWriteError = true;
      final adapter = FakeAdapter((o) async {
        return switch ('${o.method} ${o.path}') {
          'POST /board-api-keys' => jsonBody(_minted(), status: 201),
          _ => fail('unexpected ${o.method} ${o.path}'),
        };
      });
      final c = await _container(keys: keys, adapter: adapter);
      await _settled(c);
      await keys.write(_instance, _record(age: const Duration(days: 8)));
      keys.failWrite = true;

      await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

      expect(
        adapter.requests.where((r) => r.path == '/cli-auth/revoke-current'),
        isEmpty,
        reason: 'a failed read-back cannot prove the write did not commit',
      );
      expect(adapter.requests.where((r) => r.method == 'DELETE'), isEmpty);
      expect((c.read(sessionControllerProvider) as SignedIn).token, 'old-key');

      keys.failRead = false;
      expect((await keys.read(_instance))?.token, 'old-key');
    },
  );

  test(
    'the old key is revoked by token when its server id is unknown',
    () async {
      final keys = InMemoryKeyStore();
      await keys.write(_instance, _record(keyId: null));
      final adapter = FakeAdapter((o) async {
        return switch ('${o.method} ${o.path}') {
          'POST /board-api-keys' => jsonBody(_minted(), status: 201),
          'POST /cli-auth/revoke-current' => jsonBody(<String, Object?>{}),
          _ => fail('unexpected ${o.method} ${o.path}'),
        };
      });
      final c = await _container(keys: keys, adapter: adapter);
      await _settled(c);
      await keys.write(
        _instance,
        _record(keyId: null, age: const Duration(days: 8)),
      );

      await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

      expect((await keys.read(_instance))?.token, 'new-key');
      expect((c.read(sessionControllerProvider) as SignedIn).token, 'new-key');
      final revokeOld = adapter.requests.singleWhere(
        (r) => r.path == '/cli-auth/revoke-current',
      );
      expect(_auth(revokeOld), 'Bearer old-key');
      expect(
        adapter.requests.where((r) => r.method == 'DELETE'),
        isEmpty,
        reason: 'there is no id to delete, so the old key is revoked by token',
      );
    },
  );

  test('a pasted key is replaced but never revoked', () async {
    final keys = InMemoryKeyStore();
    await keys.write(_instance, _record(origin: KeyOrigin.pasted));
    final adapter = FakeAdapter((o) async {
      return switch ('${o.method} ${o.path}') {
        'POST /board-api-keys' => jsonBody(_minted(), status: 201),
        _ => fail('unexpected ${o.method} ${o.path}'),
      };
    });
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    await keys.write(
      _instance,
      _record(age: const Duration(days: 8), origin: KeyOrigin.pasted),
    );

    await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

    final stored = await keys.read(_instance);
    expect(stored?.token, 'new-key');
    expect(stored?.origin, KeyOrigin.minted);
    expect((c.read(sessionControllerProvider) as SignedIn).token, 'new-key');
    expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
      'POST /board-api-keys',
    ], reason: 'a pasted key may be in use elsewhere, so it is not revoked');
  });

  test('a record without provenance is replaced but never revoked', () async {
    final keys = InMemoryKeyStore();
    await keys.write(_instance, _record());
    final adapter = FakeAdapter((o) async {
      return switch ('${o.method} ${o.path}') {
        'POST /board-api-keys' => jsonBody(_minted(), status: 201),
        _ => fail('unexpected ${o.method} ${o.path}'),
      };
    });
    final c = await _container(keys: keys, adapter: adapter);
    await _settled(c);
    // A record written by an earlier app revision has no origin field. It may
    // hold a key the user pasted in, so rotation must not revoke the old key.
    final raw = jsonEncode({
      'token': 'old-key',
      'keyId': 'key-old',
      'createdAt': _now
          .subtract(const Duration(days: 8))
          .toUtc()
          .toIso8601String(),
    });
    await keys.write(_instance, StoredKey.decode(raw, now: _now));

    await c.read(sessionControllerProvider.notifier).rotateIfNeeded();

    final stored = await keys.read(_instance);
    expect(stored?.token, 'new-key');
    expect((c.read(sessionControllerProvider) as SignedIn).token, 'new-key');
    expect(
      adapter.requests.map((r) => '${r.method} ${r.path}'),
      ['POST /board-api-keys'],
      reason:
          'a record without provenance may hold a pasted key, so the old '
          'key is left valid',
    );
  });
}

/// [AppPrefs] that holds the cache clear open, to interrupt a sign-out.
class _GatedPrefs extends AppPrefs {
  new(super._prefs);

  final Completer<void> clearStarted = Completer<void>();
  final Completer<void> releaseClear = Completer<void>();

  @override
  Future<void> clearCachedData() async {
    if (!clearStarted.isCompleted) clearStarted.complete();
    await releaseClear.future;
    await super.clearCachedData();
  }
}

/// [KeyStore] that can hold a write open, to interleave a sign-out.
class _GatedKeyStore implements KeyStore {
  final InMemoryKeyStore _inner = InMemoryKeyStore();

  bool gateWrites = false;

  /// When set, only a write for this token is held open.
  String? gateToken;

  /// When true, [delete] throws before removing the entry.
  bool failDelete = false;

  /// Tokens whose write ran to completion, in order.
  final List<String> committedTokens = <String>[];

  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();

  @override
  Future<StoredKey?> read(String instanceKey) => _inner.read(instanceKey);

  @override
  Future<void> write(String instanceKey, StoredKey key) async {
    final held = gateWrites || (gateToken != null && key.token == gateToken);
    if (held) {
      if (!writeStarted.isCompleted) writeStarted.complete();
      await releaseWrite.future;
    }
    await _inner.write(instanceKey, key);
    committedTokens.add(key.token);
  }

  @override
  Future<void> delete(String instanceKey) async {
    if (failDelete) throw StateError('injected delete failure');
    await _inner.delete(instanceKey);
  }

  @override
  Future<void> markSignOutPending(String instanceKey, Set<String> tokens) =>
      _inner.markSignOutPending(instanceKey, tokens);

  @override
  Future<Set<String>> signOutPendingSessions(String instanceKey) =>
      _inner.signOutPendingSessions(instanceKey);

  @override
  Future<void> clearSignOutPending(String instanceKey) =>
      _inner.clearSignOutPending(instanceKey);

  @override
  Future<Map<String, StoredKey>> readAll() => _inner.readAll();
}
