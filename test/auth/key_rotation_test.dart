import 'dart:async';
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
}) => StoredKey(
  token: token,
  keyId: keyId,
  createdAt: _now.subtract(age),
  expiresAt: expiresAt,
);

Future<ProviderContainer> _container({
  required KeyStore keys,
  required FakeAdapter adapter,
}) async {
  SharedPreferences.setMockInitialValues({'last_base_url': _instance});
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appPrefsProvider.overrideWithValue(
        AppPrefs(await SharedPreferences.getInstance()),
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
    await notifier.signOut();
    keys.releaseWrite.complete();
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
  });
}

/// [KeyStore] that can hold a write open, to interleave a sign-out.
class _GatedKeyStore implements KeyStore {
  final InMemoryKeyStore _inner = InMemoryKeyStore();

  bool gateWrites = false;
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();

  @override
  Future<StoredKey?> read(String instanceKey) => _inner.read(instanceKey);

  @override
  Future<void> write(String instanceKey, StoredKey key) async {
    if (gateWrites) {
      if (!writeStarted.isCompleted) writeStarted.complete();
      await releaseWrite.future;
    }
    await _inner.write(instanceKey, key);
  }

  @override
  Future<void> delete(String instanceKey) => _inner.delete(instanceKey);

  @override
  Future<Map<String, StoredKey>> readAll() => _inner.readAll();
}
