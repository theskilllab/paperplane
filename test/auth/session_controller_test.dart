import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_adapter.dart';

const _instance = 'https://paperclip.example.test';
final String _key = ['pcp', 'board', 'fake0123456789abcdef'].join('_');

Future<ProviderContainer> makeContainer({
  Map<String, Object> prefs = const {},
  Map<String, String> keys = const {},
  AppEnv env = const AppEnv(),
  FakeAdapter? adapter,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = InMemoryKeyStore();
  for (final entry in keys.entries) {
    await store.write(entry.key, entry.value);
  }
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appPrefsProvider.overrideWithValue(
        AppPrefs(await SharedPreferences.getInstance()),
      ),
      keyStoreProvider.overrideWithValue(store),
      appEnvProvider.overrideWith(() => AppEnvController(env)),
      if (adapter != null) httpAdapterProvider.overrideWithValue(adapter),
    ],
  );
  addTearDown(container.dispose);
  // Keep the controller alive while it restores.
  container.listen(sessionControllerProvider, (_, _) {});
  return container;
}

Future<SessionState> settled(ProviderContainer c) =>
    pumpEventQueue().then((_) => c.read(sessionControllerProvider));

void main() {
  test('is restoring first, then signed out when nothing is stored', () async {
    final c = await makeContainer();
    expect(c.read(sessionControllerProvider), isA<SessionRestoring>());
    final state = await settled(c);
    expect(state, isA<SignedOut>());
    expect((state as SignedOut).lastBaseUrl, isNull);
    expect(state.reason, SignedOutReason.none);
  });

  test('restores a stored key for the last address', () async {
    final c = await makeContainer(
      prefs: {'last_base_url': _instance},
      keys: {_instance: _key},
    );
    final state = await settled(c);
    expect(state, isA<SignedIn>());
    final signedIn = state as SignedIn;
    expect(signedIn.baseUrl.toString(), _instance);
    expect(signedIn.token, _key);
    expect(signedIn.isDemo, isFalse);
  });

  test('a stored address without a key prefills sign-in', () async {
    final c = await makeContainer(prefs: {'last_base_url': _instance});
    final state = await settled(c) as SignedOut;
    expect(state.lastBaseUrl, _instance);
    expect(state.reason, SignedOutReason.none);
  });

  test('a corrupt stored address is ignored', () async {
    final c = await makeContainer(
      prefs: {'last_base_url': 'https://not a url'},
    );
    final state = await settled(c) as SignedOut;
    expect(state.lastBaseUrl, isNull);
  });

  test(
    'signIn stores the key per instance and remembers the address',
    () async {
      final c = await makeContainer();
      await settled(c);
      await c
          .read(sessionControllerProvider.notifier)
          .signIn(baseUrl: Uri.parse(_instance), token: _key);

      final state = c.read(sessionControllerProvider) as SignedIn;
      expect(state.token, _key);
      expect(await c.read(keyStoreProvider).read(_instance), _key);
      expect(c.read(appPrefsProvider).lastBaseUrl, _instance);
    },
  );

  test('keys of different instances do not mix', () async {
    final c = await makeContainer();
    await settled(c);
    final notifier = c.read(sessionControllerProvider.notifier);
    await notifier.signIn(baseUrl: Uri.parse(_instance), token: _key);
    await notifier.signIn(
      baseUrl: Uri.parse('https://other.example.test'),
      token: 'other',
    );
    final store = c.read(keyStoreProvider);
    expect(await store.read(_instance), _key);
    expect(await store.read('https://other.example.test'), 'other');
  });

  test('SignedIn never prints the key', () async {
    final signedIn = SignedIn(baseUrl: Uri.parse(_instance), token: _key);
    expect('$signedIn', isNot(contains(_key)));
    expect('$signedIn', isNot(contains('pcp_board_')));
  });

  test('401 clears the key and goes to S1 with the address (G3)', () async {
    final c = await makeContainer(
      prefs: {'last_base_url': _instance},
      keys: {_instance: _key},
    );
    await settled(c);

    await c.read(sessionControllerProvider.notifier).handleUnauthorized();

    final state = c.read(sessionControllerProvider) as SignedOut;
    expect(state.reason, SignedOutReason.expired);
    expect(state.lastBaseUrl, _instance);
    expect(await c.read(keyStoreProvider).read(_instance), isNull);
  });

  test(
    'a late 401 for a previous key does not sign out the new session',
    () async {
      final c = await makeContainer(
        prefs: {'last_base_url': _instance},
        keys: {_instance: _key},
      );
      await settled(c);

      await c
          .read(sessionControllerProvider.notifier)
          .handleUnauthorized('a-key-from-an-earlier-session');

      final state = c.read(sessionControllerProvider);
      expect(state, isA<SignedIn>());
      expect((state as SignedIn).token, _key);
      expect(await c.read(keyStoreProvider).read(_instance), _key);
    },
  );

  test('a 401 for the current key still signs out', () async {
    final c = await makeContainer(
      prefs: {'last_base_url': _instance},
      keys: {_instance: _key},
    );
    await settled(c);
    await c.read(sessionControllerProvider.notifier).handleUnauthorized(_key);
    expect(c.read(sessionControllerProvider), isA<SignedOut>());
  });

  test(
    'a key left in the iOS Keychain by an earlier install is removed',
    () async {
      final c = await makeContainer(
        keys: {'https://old.example.test': 'orphaned-key'},
      );
      final state = await settled(c);
      expect(state, isA<SignedOut>());
      expect(
        await c.read(keyStoreProvider).read('https://old.example.test'),
        isNull,
      );
    },
  );

  test('a key for the stored address is not treated as orphaned', () async {
    final c = await makeContainer(
      prefs: {'last_base_url': _instance},
      keys: {_instance: _key},
    );
    final state = await settled(c);
    expect(state, isA<SignedIn>());
    expect(await c.read(keyStoreProvider).read(_instance), _key);
  });

  test('handleUnauthorized twice is harmless', () async {
    final c = await makeContainer(
      prefs: {'last_base_url': _instance},
      keys: {_instance: _key},
    );
    await settled(c);
    final notifier = c.read(sessionControllerProvider.notifier);
    await Future.wait([
      notifier.handleUnauthorized(),
      notifier.handleUnauthorized(),
    ]);
    expect(
      (c.read(sessionControllerProvider) as SignedOut).reason,
      SignedOutReason.expired,
    );
  });

  test('signIn clears cached server data from the previous account', () async {
    final c = await makeContainer(
      prefs: {
        'cached_companies': '[{"id":"old"}]',
        'cached_feed': '{}',
        'cached_feed_company': 'old',
        'cached_feed_at': 1,
      },
    );
    await settled(c);
    await c
        .read(sessionControllerProvider.notifier)
        .signIn(baseUrl: Uri.parse(_instance), token: _key);
    final prefs = c.read(appPrefsProvider);
    expect(prefs.cachedCompaniesJson, isNull);
    expect(prefs.cachedFeedJson, isNull);
    expect(prefs.cachedFeedCompanyId, isNull);
    expect(prefs.cachedFeedAt, isNull);
  });

  test('signOut records that the user asked for it', () async {
    final c = await makeContainer(
      prefs: {'last_base_url': _instance},
      keys: {_instance: _key},
    );
    await settled(c);
    await c.read(sessionControllerProvider.notifier).signOut();
    final state = c.read(sessionControllerProvider) as SignedOut;
    expect(state.reason, SignedOutReason.userRequested);
    expect(await c.read(keyStoreProvider).read(_instance), isNull);
  });

  test('demo mode is signed in with no key and touches no storage', () async {
    final c = await makeContainer(env: const AppEnv(demo: true));
    final state = c.read(sessionControllerProvider) as SignedIn;
    expect(state.isDemo, isTrue);
    expect(state.token, isNull);

    await c.read(sessionControllerProvider.notifier).handleUnauthorized();
    expect(c.read(sessionControllerProvider), isA<SignedIn>());
    expect(c.read(appPrefsProvider).lastBaseUrl, isNull);
  });

  test('entering demo mode signs in; leaving it returns to sign-in', () async {
    final c = await makeContainer();
    await settled(c);
    expect(c.read(sessionControllerProvider), isA<SignedOut>());

    c.read(appEnvProvider.notifier).enterDemo();
    expect((c.read(sessionControllerProvider) as SignedIn).isDemo, isTrue);

    c.read(appEnvProvider.notifier).exitDemo();
    await settled(c);
    expect(c.read(sessionControllerProvider), isA<SignedOut>());
  });

  group('api client wiring', () {
    test('sends the key; a 401 signs the user out', () async {
      final adapter = FakeAdapter((o) async => jsonBody(null, status: 401));
      final c = await makeContainer(
        prefs: {'last_base_url': _instance},
        keys: {_instance: _key},
        adapter: adapter,
      );
      await settled(c);

      await expectLater(
        c.read(sessionRepositoryProvider).me(),
        throwsA(isA<Unauthorized>()),
      );
      await pumpEventQueue();

      expect(adapter.requests.single.headers['Authorization'], 'Bearer $_key');
      final state = c.read(sessionControllerProvider) as SignedOut;
      expect(state.reason, SignedOutReason.expired);
      expect(await c.read(keyStoreProvider).read(_instance), isNull);
    });

    test(
      'while signed out, calls fail with Unauthorized and do not loop',
      () async {
        final c = await makeContainer();
        await settled(c);
        await expectLater(
          c.read(companyRepositoryProvider).listCompanies(),
          throwsA(isA<Unauthorized>()),
        );
        expect(
          (c.read(sessionControllerProvider) as SignedOut).reason,
          SignedOutReason.none,
        );
      },
    );

    test('demo mode uses fake repositories and never the network', () async {
      final adapter = FakeAdapter((o) async => throw StateError('network!'));
      final c = await makeContainer(
        env: const AppEnv(demo: true),
        adapter: adapter,
      );
      expect(
        await c.read(companyRepositoryProvider).listCompanies(),
        hasLength(2),
      );
      expect(
        (await c.read(inboxRepositoryProvider).fetchAttention('x')).items,
        isNotEmpty,
      );
      expect(adapter.requests, isEmpty);
    });
  });

  test('AppPrefs remembers the company and can forget it', () async {
    final c = await makeContainer();
    final prefs = c.read(appPrefsProvider);
    expect(prefs.lastCompanyId, isNull);
    await prefs.setLastCompanyId('c1');
    expect(prefs.lastCompanyId, 'c1');
    await prefs.setLastCompanyId(null);
    expect(prefs.lastCompanyId, isNull);
  });
}
