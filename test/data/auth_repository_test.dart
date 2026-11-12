import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/device_login.dart';
import 'package:paperplane/api/models/health.dart';
import 'package:paperplane/data/auth_repository.dart';

import '../support/fake_adapter.dart';

const _base = 'https://paperclip.example.test';
const _key = 'test-board-key';

Map<String, Object?> _sessionJson({
  List<String> companies = const ['company-1'],
}) => {
  'user': {
    'id': 'user-1',
    'name': 'Test Person',
    'email': 'person@example.test',
  },
  'companyIds': companies,
  'keyId': 'key-1',
};

void main() {
  final base = Uri.parse(_base);
  final now = DateTime.utc(2026, 11, 12, 12);

  HttpAuthRepository repository(FakeAdapter adapter) =>
      HttpAuthRepository(adapter: adapter, now: () => now);

  group('password-first sign-in', () {
    test('signs in, mints an explicit 30-day key, verifies, discards the '
        'browser session', () async {
      final adapter = FakeAdapter((o) async {
        switch ('${o.method} ${o.path}') {
          case 'POST /auth/sign-in/email':
            return jsonBody(
              <String, Object?>{},
              headers: {
                'set-cookie': ['session=abc123; Path=/; HttpOnly'],
              },
            );
          case 'POST /board-api-keys':
            return jsonBody({
              'id': 'key-new',
              'name': 'Paperplane (Test Phone)',
              'token': _key,
              'expiresAt': now.add(const Duration(days: 30)).toIso8601String(),
            }, status: 201);
          case 'GET /cli-auth/me':
            return jsonBody(_sessionJson());
          case 'POST /auth/sign-out':
            return jsonBody(<String, Object?>{});
          default:
            fail('unexpected ${o.method} ${o.path}');
        }
      });

      final result = await repository(adapter).signIn(
        baseUrl: base,
        email: 'person@example.test',
        password: 'correct horse',
        keyName: 'Paperplane (Test Phone)',
      );

      expect(result.token, _key);
      expect(result.info.companyIds, ['company-1']);

      final mint = adapter.requests.singleWhere(
        (r) => r.path == '/board-api-keys',
      );
      expect(mint.headers['Origin'], _base);
      expect(mint.headers['Cookie'], 'session=abc123');
      expect(mint.data, {
        'name': 'Paperplane (Test Phone)',
        'expiresAt': now.add(const Duration(days: 30)).toIso8601String(),
      });

      final signIn = adapter.requests.first;
      expect(signIn.headers['Origin'], _base);
      expect(signIn.data, {
        'email': 'person@example.test',
        'password': 'correct horse',
      });

      final me = adapter.requests.singleWhere((r) => r.path == '/cli-auth/me');
      expect(me.headers['Authorization'], 'Bearer $_key');

      final signOut = adapter.requests.singleWhere(
        (r) => r.path == '/auth/sign-out',
      );
      expect(signOut.headers['Cookie'], 'session=abc123');
      expect(signOut.headers['Origin'], _base);
    });

    test('a wrong password is Unauthorized and mints nothing', () async {
      final adapter = FakeAdapter((o) async => jsonBody(null, status: 401));
      await expectLater(
        repository(adapter).signIn(
          baseUrl: base,
          email: 'person@example.test',
          password: 'wrong',
          keyName: 'Paperplane (Test Phone)',
        ),
        throwsA(isA<Unauthorized>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    test(
      'an account with no company is rejected and the key revoked',
      () async {
        final adapter = FakeAdapter((o) async {
          return switch ('${o.method} ${o.path}') {
            'POST /auth/sign-in/email' => jsonBody(
              <String, Object?>{},
              headers: {
                'set-cookie': ['session=abc; Path=/'],
              },
            ),
            'POST /board-api-keys' => jsonBody({'token': _key}, status: 201),
            'GET /cli-auth/me' => jsonBody(_sessionJson(companies: [])),
            'POST /cli-auth/revoke-current' => jsonBody(<String, Object?>{}),
            _ => jsonBody(<String, Object?>{}),
          };
        });

        await expectLater(
          repository(adapter).signIn(
            baseUrl: base,
            email: 'person@example.test',
            password: 'pw',
            keyName: 'Paperplane (Test Phone)',
          ),
          throwsA(isA<NoCompanyOnAccount>()),
        );
        expect(
          adapter.requests.map((r) => r.path),
          contains('/cli-auth/revoke-current'),
        );
      },
    );

    test('a failure after minting revokes the new key', () async {
      final adapter = FakeAdapter((o) async {
        return switch ('${o.method} ${o.path}') {
          'POST /auth/sign-in/email' => jsonBody(
            <String, Object?>{},
            headers: {
              'set-cookie': ['session=abc; Path=/'],
            },
          ),
          'POST /board-api-keys' => jsonBody({'token': _key}, status: 201),
          'GET /cli-auth/me' => jsonBody(null, status: 500),
          'POST /cli-auth/revoke-current' => jsonBody(<String, Object?>{}),
          _ => jsonBody(<String, Object?>{}),
        };
      });

      await expectLater(
        repository(adapter).signIn(
          baseUrl: base,
          email: 'person@example.test',
          password: 'pw',
          keyName: 'Paperplane (Test Phone)',
        ),
        throwsA(isA<Server>()),
      );
      final revoke = adapter.requests.singleWhere(
        (r) => r.path == '/cli-auth/revoke-current',
      );
      expect(revoke.headers['Authorization'], 'Bearer $_key');
    });

    test('the browser cookie is never stored in the result', () async {
      final adapter = FakeAdapter((o) async {
        return switch ('${o.method} ${o.path}') {
          'POST /auth/sign-in/email' => jsonBody(
            <String, Object?>{},
            headers: {
              'set-cookie': ['session=secret-cookie; Path=/'],
            },
          ),
          'POST /board-api-keys' => jsonBody({'token': _key}, status: 201),
          'GET /cli-auth/me' => jsonBody(_sessionJson()),
          _ => jsonBody(<String, Object?>{}),
        };
      });

      final result = await repository(adapter).signIn(
        baseUrl: base,
        email: 'person@example.test',
        password: 'pw',
        keyName: 'Paperplane (Test Phone)',
      );
      expect('$result', isNot(contains('secret-cookie')));
    });
  });

  group('paste token', () {
    test('verifies the pasted key with one authenticated call', () async {
      final adapter = FakeAdapter((o) async {
        expect(o.path, '/cli-auth/me');
        return jsonBody(_sessionJson());
      });
      final result = await repository(adapter)
          .verifyKey(baseUrl: base, token: _key);
      expect(result.token, _key);
      expect(adapter.requests.single.headers['Authorization'], 'Bearer $_key');
    });

    test('an empty key makes no call', () async {
      final adapter = FakeAdapter((o) async => jsonBody(_sessionJson()));
      await expectLater(
        repository(adapter).verifyKey(baseUrl: base, token: ''),
        throwsA(isA<Unauthorized>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('a key with no company is rejected', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(_sessionJson(companies: [])),
      );
      await expectLater(
        repository(adapter).verifyKey(baseUrl: base, token: _key),
        throwsA(isA<NoCompanyOnAccount>()),
      );
    });
  });

  group('health', () {
    test('parses authenticated and local_trusted', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody({
          'status': 'ok',
          'deploymentMode': 'local_trusted',
          'deploymentExposure': 'private',
        }),
      );
      final health = await repository(adapter).health(base);
      expect(health.isHealthy, isTrue);
      expect(health.mode, DeploymentMode.localTrusted);
    });
  });

  group('device login', () {
    Map<String, Object?> challengeJson() => {
      'id': 'challenge-1',
      'token': 'challenge-secret',
      'boardApiToken': _key,
      'approvalPath': '/cli-auth/challenges/challenge-1',
      'approvalUrl': 'https://evil.example.test/approve',
      'pollPath': '/cli-auth/challenges/challenge-1',
      'expiresAt': now.add(const Duration(minutes: 10)).toIso8601String(),
      'suggestedPollIntervalMs': 1000,
    };

    test(
      'creates a challenge and prefers approvalPath on the session host',
      () async {
        final adapter = FakeAdapter(
          (o) async => jsonBody(challengeJson(), status: 201),
        );
        final challenge = await repository(adapter).startDeviceLogin(
          baseUrl: base,
          clientName: 'Paperplane (Test Phone)',
        );

        expect(challenge.boardApiToken, _key);
        expect(challenge.pollInterval, const Duration(seconds: 1));
        expect(
          repository(adapter).approvalUri(base, challenge).toString(),
          'https://paperclip.example.test/cli-auth/challenges/challenge-1',
          reason: 'the absolute approval URL points at another host',
        );
        expect(adapter.requests.single.data, {
          'command': 'paperplane',
          'clientName': 'Paperplane (Test Phone)',
        });
      },
    );

    test(
      'polls without a duplicate /api prefix and reports approved',
      () async {
        final adapter = FakeAdapter((o) async {
          if (o.path == '/cli-auth/challenges/challenge-1') {
            expect(o.queryParameters['token'], 'challenge-secret');
            return jsonBody({'status': 'approved'});
          }
          return jsonBody(challengeJson(), status: 201);
        });
        final repo = repository(adapter);
        final challenge = await repo.startDeviceLogin(
          baseUrl: base,
          clientName: 'Paperplane (Test Phone)',
        );
        final status = await repo.pollDeviceLogin(
          baseUrl: base,
          challenge: challenge,
        );
        expect(status, DeviceLoginStatus.approved);
        expect(
          adapter.requests.last.uri.toString(),
          contains('/api/cli-auth/'),
        );
      },
    );

    test('reports pending, denied and expired', () async {
      for (final (wire, expected) in [
        ('pending', DeviceLoginStatus.pending),
        ('denied', DeviceLoginStatus.denied),
        ('expired', DeviceLoginStatus.expired),
      ]) {
        final adapter = FakeAdapter((o) async => jsonBody({'status': wire}));
        final status = await repository(adapter).pollDeviceLogin(
          baseUrl: base,
          challenge: DeviceChallenge.fromJson(challengeJson()),
        );
        expect(status, expected, reason: wire);
      }
    });

    test('a local expiry wins over a pending answer', () async {
      final adapter = FakeAdapter((o) async => jsonBody({'status': 'pending'}));
      final expired = DeviceChallenge.fromJson({
        ...challengeJson(),
        'expiresAt': now.subtract(const Duration(seconds: 1)).toIso8601String(),
      });
      final status = await repository(adapter)
          .pollDeviceLogin(baseUrl: base, challenge: expired);
      expect(status, DeviceLoginStatus.expired);
    });

    test('cancel tells the server and swallows a failure', () async {
      final adapter = FakeAdapter((o) async {
        if (o.path.endsWith('/cancel')) return jsonBody(null, status: 500);
        return jsonBody(challengeJson(), status: 201);
      });
      final repo = repository(adapter);
      final challenge = await repo.startDeviceLogin(
        baseUrl: base,
        clientName: 'Paperplane (Test Phone)',
      );
      await repo.cancelDeviceLogin(baseUrl: base, challenge: challenge);
      final cancel = adapter.requests.last;
      expect(cancel.path, '/cli-auth/challenges/challenge-1/cancel');
      expect(cancel.data, {'token': 'challenge-secret'});
    });

    test(
      'a poll path cannot send the challenge token to another host',
      () async {
        final challenge = DeviceChallenge.fromJson({
          ...challengeJson(),
          'pollPath': 'https://evil.example.test/steal',
        });
        final adapter = FakeAdapter(
          (o) async => jsonBody({'status': 'pending'}),
        );
        await expectLater(
          repository(adapter)
              .pollDeviceLogin(baseUrl: base, challenge: challenge),
          throwsA(isA<Unexpected>()),
        );
        expect(adapter.requests, isEmpty);
      },
    );

    test('an incomplete challenge is rejected', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody({'id': 'x'}, status: 201),
      );
      await expectLater(
        repository(adapter).startDeviceLogin(
          baseUrl: base,
          clientName: 'Paperplane (Test Phone)',
        ),
        throwsA(isA<Unexpected>()),
      );
    });

    test('an absolute approval URL on another host is not used', () {
      final challenge = DeviceChallenge.fromJson({
        ...challengeJson(),
        'approvalPath': null,
      });
      expect(
        repository(FakeAdapter((o) async => jsonBody({})))
            .approvalUri(base, challenge),
        isNull,
      );
    });
  });
}
