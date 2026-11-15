import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/api_error.dart';

import '../support/fake_adapter.dart';

void main() {
  final base = Uri.parse('https://paperclip.example.test');
  final key = ['pcp', 'board', 'fake0123456789abcdef'].join('_');

  ApiClient client(
    FakeAdapter adapter, {
    String? token,
    void Function(String)? onUnauthorized,
    void Function(String)? log,
  }) => ApiClient(
    baseUrl: base,
    adapter: adapter,
    tokenProvider: () => token,
    onUnauthorized: onUnauthorized,
    log: log,
  );

  Future<ApiError> errorOf(
    FakeAdapter adapter, {
    bool stateConflict = false,
    String? token,
    void Function(String)? onUnauthorized,
  }) async {
    final c = client(adapter, token: token, onUnauthorized: onUnauthorized);
    try {
      await c.post('/x', stateConflict: stateConflict);
    } on ApiError catch (e) {
      return e;
    }
    fail('expected an ApiError');
  }

  test('a 3xx gives Redirected and sends no second request', () async {
    final adapter = FakeAdapter(
      (o) async => jsonBody(
        <String, Object?>{},
        status: 301,
        headers: {
          'location': ['https://paperclip.example.test/api/x'],
        },
      ),
    );

    final error = await errorOf(adapter, token: key);

    expect(error, isA<Redirected>());
    expect(adapter.requests, hasLength(1));
  });

  group('requests', () {
    test(
      'prefixes /api, sends the Bearer key and returns JSON and ETag',
      () async {
        final adapter = FakeAdapter(
          (o) async => jsonBody(
            {'ok': true},
            headers: {
              'etag': ['"v1"'],
            },
          ),
        );
        final response = await client(adapter, token: key).get('/health');

        final sent = adapter.requests.single;
        expect(
          sent.uri.toString(),
          'https://paperclip.example.test/api/health',
        );
        expect(sent.headers['Authorization'], 'Bearer $key');
        expect(response.data, {'ok': true});
        expect(response.etag, '"v1"');
        expect(response.notModified, isFalse);
      },
    );

    test('sends no Authorization header without a key', () async {
      final adapter = FakeAdapter((o) async => jsonBody(<String, Object?>{}));
      await client(adapter).get('/health');
      expect(adapter.requests.single.headers, isNot(contains('Authorization')));
    });

    test('sends If-None-Match and maps 304 to notModified', () async {
      final adapter = FakeAdapter((o) async => emptyBody(304));
      final response = await client(adapter).get('/a', ifNoneMatch: '"v1"');
      expect(adapter.requests.single.headers['If-None-Match'], '"v1"');
      expect(response.notModified, isTrue);
      expect(response.data, anyOf(isNull, ''));
    });

    test('passes query parameters', () async {
      final adapter = FakeAdapter((o) async => jsonBody(<String, Object?>{}));
      await client(adapter).get('/a', query: {'limit': 100});
      expect(adapter.requests.single.uri.query, 'limit=100');
    });
  });

  group('error mapping', () {
    Future<ApiError> forStatus(
      int code, {
      Object? body,
      Map<String, List<String>> headers = const {},
      bool stateConflict = false,
    }) => errorOf(
      FakeAdapter((o) async => jsonBody(body, status: code, headers: headers)),
      stateConflict: stateConflict,
    );

    test('401 is Unauthorized', () async {
      expect(await forStatus(401), isA<Unauthorized>());
    });

    test('403 is Forbidden with the server message', () async {
      final e = await forStatus(403, body: {'error': 'Board only'});
      expect(e, isA<Forbidden>());
      expect((e as Forbidden).message, 'Board only');
    });

    test('403 with a nested message still yields it', () async {
      final e = await forStatus(
        403,
        body: {
          'error': {'message': 'Nope', 'code': 'x'},
        },
      );
      expect((e as Forbidden).message, 'Nope');
    });

    test('403 about the hostname is HostNotAllowed', () async {
      final e = await forStatus(
        403,
        body: {
          'error': 'This hostname is not allowed for this Paperclip instance',
        },
      );
      expect(e, isA<HostNotAllowed>());
    });

    test('404 is NotFound', () async {
      expect(await forStatus(404), isA<NotFound>());
    });

    test('409 and 422 are AlreadyHandled only for decision calls', () async {
      for (final code in [409, 422]) {
        final decision = await forStatus(code, stateConflict: true);
        expect(decision, isA<AlreadyHandled>());
        expect((decision as AlreadyHandled).status, code);

        final other = await forStatus(code);
        expect(other, isA<Server>());
        expect((other as Server).status, code);
      }
    });

    test('AlreadyHandled ignores the message text', () async {
      final e = await forStatus(
        422,
        body: {'error': 'something else entirely'},
        stateConflict: true,
      );
      expect(e, isA<AlreadyHandled>());
    });

    test('429 carries Retry-After', () async {
      final e = await forStatus(
        429,
        headers: {
          'retry-after': ['7'],
        },
      );
      expect(e, isA<RateLimited>());
      expect((e as RateLimited).retryAfter, const Duration(seconds: 7));
    });

    test('429 without the header has no retryAfter', () async {
      final e = await forStatus(429);
      expect((e as RateLimited).retryAfter, isNull);
    });

    test('429 reads X-Retry-After (better-auth)', () async {
      final e = await forStatus(
        429,
        headers: {
          'x-retry-after': ['10'],
        },
      );
      expect((e as RateLimited).retryAfter, const Duration(seconds: 10));
    });

    test('5xx and other 4xx are Server(status)', () async {
      for (final code in [400, 500, 502, 503]) {
        final e = await forStatus(code);
        expect(e, isA<Server>(), reason: '$code');
        expect((e as Server).status, code);
      }
    });

    test('socket failure is Offline', () async {
      final e = await errorOf(
        FakeAdapter(
          (o) async => throw DioException.connectionError(
            requestOptions: o,
            reason: 'x',
            error: const SocketException('no route'),
          ),
        ),
      );
      expect(e, isA<Offline>());
    });

    test('timeouts are TimedOut', () async {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final e = await errorOf(
          FakeAdapter(
            (o) async => throw DioException(requestOptions: o, type: type),
          ),
        );
        expect(e, isA<TimedOut>(), reason: '$type');
      }
    });

    test('certificate and handshake failures are Tls', () async {
      final bad = await errorOf(
        FakeAdapter(
          (o) async => throw DioException.badCertificate(requestOptions: o),
        ),
      );
      expect(bad, isA<Tls>());

      final handshake = await errorOf(
        FakeAdapter(
          (o) async => throw DioException(
            requestOptions: o,
            error: const HandshakeException('bad'),
          ),
        ),
      );
      expect(handshake, isA<Tls>());
    });

    test('anything else is Unexpected, never a raw exception', () async {
      final e = await errorOf(
        FakeAdapter(
          (o) async =>
              throw DioException(requestOptions: o, error: StateError('boom')),
        ),
      );
      expect(e, isA<Unexpected>());
    });

    test('a non-Dio exception is also wrapped', () async {
      final e = await errorOf(FakeAdapter((o) async => throw StateError('x')));
      expect(e, isA<Unexpected>());
    });
  });

  group('onUnauthorized', () {
    test('fires on 401 when a key was sent and names that key', () async {
      String? used;
      await errorOf(
        FakeAdapter((o) async => jsonBody(null, status: 401)),
        token: key,
        onUnauthorized: (token) => used = token,
      );
      expect(used, key);
    });

    test(
      'an explicit Authorization header wins and is the key reported',
      () async {
        String? used;
        final adapter = FakeAdapter((o) async => jsonBody(null, status: 401));
        final c = client(adapter, token: key, onUnauthorized: (t) => used = t);
        await expectLater(
          c.get(
            '/cli-auth/me',
            headers: {'Authorization': 'Bearer pasted-key'},
          ),
          throwsA(isA<Unauthorized>()),
        );
        expect(
          adapter.requests.single.headers['Authorization'],
          'Bearer pasted-key',
        );
        expect(used, 'pasted-key');
      },
    );

    test(
      'does not fire on 401 without a key (wrong password at sign-in)',
      () async {
        var calls = 0;
        await errorOf(
          FakeAdapter((o) async => jsonBody(null, status: 401)),
          onUnauthorized: (_) => calls++,
        );
        expect(calls, 0);
      },
    );

    test('does not fire for other errors', () async {
      var calls = 0;
      await errorOf(
        FakeAdapter((o) async => jsonBody(null, status: 403)),
        token: key,
        onUnauthorized: (_) => calls++,
      );
      expect(calls, 0);
    });
  });

  group('signedOut client', () {
    test('fails every call with Unauthorized and no callback', () async {
      final c = ApiClient.signedOut();
      await expectLater(c.get('/companies'), throwsA(isA<Unauthorized>()));
    });
  });

  group('scopes', () {
    test('cancelScope aborts calls in that scope only', () async {
      final gate = Completer<void>();
      final adapter = FakeAdapter((o) async {
        await gate.future;
        return jsonBody({'ok': true});
      });
      final c = client(adapter);

      final a = c.get('/a', scope: 'company-1');
      final b = c.get('/b', scope: 'company-2');
      final aOutcome = a.then<Object?>((r) => r, onError: (Object e) => e);
      c.cancelScope('company-1');
      gate.complete();

      expect(await aOutcome, isA<Unexpected>());
      expect((await b).data, {'ok': true});
    });
  });

  group('logging', () {
    test(
      'logs method, path and status, never key, host, query or body',
      () async {
        final lines = <String>[];
        final adapter = FakeAdapter(
          (o) async => jsonBody({'token': key, 'secret': 'hunter2'}),
        );
        final c = client(adapter, token: key, log: lines.add);

        await c.post('/board-api-keys', body: {'password': 'hunter2'});
        await c.get('/companies/c1/attention', query: {'limit': 100});

        final all = lines.join('\n');
        expect(all, contains('POST /board-api-keys -> 200'));
        expect(all, contains('GET /companies/c1/attention -> 200'));
        expect(all, isNot(contains(key)));
        expect(all, isNot(contains('hunter2')));
        expect(all, isNot(contains('paperclip.example.test')));
        expect(all, isNot(contains('limit=100')));
        expect(all, contains('[redacted]'));
      },
    );

    test('logs failures without credentials too', () async {
      final lines = <String>[];
      final c = client(
        FakeAdapter((o) async => jsonBody(null, status: 401)),
        token: key,
        log: lines.add,
      );
      await expectLater(c.get('/cli-auth/me'), throwsA(isA<Unauthorized>()));
      expect(lines.join(), contains('401'));
      expect(lines.join(), isNot(contains(key)));
    });
  });
}
