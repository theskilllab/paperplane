import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/health.dart';
import 'package:paperplane/data/company_repository.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/data/inbox_repository.dart';
import 'package:paperplane/data/session_repository.dart';

import '../support/fake_adapter.dart';
import '../support/fixtures.dart';

ApiClient clientFor(FakeAdapter adapter) => ApiClient(
  baseUrl: Uri.parse('https://paperclip.example.test'),
  adapter: adapter,
);

void main() {
  group('Http repositories', () {
    test('session: health, me and revoke use the right endpoints', () async {
      final adapter = FakeAdapter((o) async {
        return switch (o.path) {
          '/health' => jsonBody(loadFixture('health.json')),
          '/cli-auth/me' => jsonBody(loadFixture('session_me.json')),
          _ => jsonBody(<String, Object?>{}),
        };
      });
      final repo = HttpSessionRepository(clientFor(adapter));

      expect((await repo.health()).mode, DeploymentMode.authenticated);
      expect((await repo.me()).keyId, 'key-demo-1');
      await repo.revokeCurrentKey();

      expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
        'GET /health',
        'GET /cli-auth/me',
        'POST /cli-auth/revoke-current',
      ]);
    });

    test('companies: GET /companies', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('companies.json')),
      );
      final companies = await HttpCompanyRepository(clientFor(adapter))
          .listCompanies();
      expect(companies, hasLength(2));
      expect(adapter.requests.single.path, '/companies');
    });

    test('inbox: limit 100 and a per-company scope', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(demoAttentionJson(DateTime.utc(2026, 1, 15, 12))),
      );
      final feed = await HttpInboxRepository(clientFor(adapter))
          .fetchAttention('company-demo-1');
      expect(feed.items, hasLength(13));
      final sent = adapter.requests.single;
      expect(sent.path, '/companies/company-demo-1/attention');
      expect(sent.queryParameters, {'limit': 100});
    });

    test(
      'inbox: replays If-None-Match and serves the cached feed on 304',
      () async {
        var calls = 0;
        final adapter = FakeAdapter((o) async {
          calls++;
          if (calls == 1) {
            return jsonBody(
              demoAttentionJson(DateTime.utc(2026, 1, 15, 12)),
              headers: {
                'etag': ['"v1"'],
              },
            );
          }
          return emptyBody(304);
        });
        final repo = HttpInboxRepository(clientFor(adapter));

        final first = await repo.fetchAttention('c1');
        final second = await repo.fetchAttention('c1');

        expect(adapter.requests[0].headers, isNot(contains('If-None-Match')));
        expect(adapter.requests[1].headers['If-None-Match'], '"v1"');
        expect(second, same(first));
      },
    );

    test('inbox: the cache is per company', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(
          demoAttentionJson(DateTime.utc(2026, 1, 15, 12)),
          headers: {
            'etag': ['"v1"'],
          },
        ),
      );
      final repo = HttpInboxRepository(clientFor(adapter));
      await repo.fetchAttention('c1');
      await repo.fetchAttention('c2');
      expect(adapter.requests[1].headers, isNot(contains('If-None-Match')));
    });

    test('inbox: errors surface as ApiError', () async {
      final adapter = FakeAdapter((o) async => jsonBody(null, status: 403));
      await expectLater(
        HttpInboxRepository(clientFor(adapter)).fetchAttention('c1'),
        throwsA(isA<Forbidden>()),
      );
    });

    test('inbox: agentNames maps id to name', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('agents.json')),
      );
      final names = await HttpInboxRepository(clientFor(adapter))
          .agentNames('c1');
      expect(names['agent-ceo'], 'Chief Example');
      expect(adapter.requests.single.path, '/companies/c1/agents');
    });
  });

  group('Fake repositories', () {
    final now = DateTime.utc(2026, 1, 15, 12);

    test('inbox serves the demo feed through the real parser', () async {
      final feed = await FakeInboxRepository(now: () => now)
          .fetchAttention(demoCompanyId);
      expect(
        {for (final i in feed.items) i.sourceKind}..remove(SourceKind.unknown),
        SourceKind.values.where((k) => k != SourceKind.unknown).toSet(),
      );
      expect(feed.generatedAt, now);
    });

    test('failWith, latency and call counting work', () async {
      final repo = FakeCompanyRepository()..failWith = const Offline();
      await expectLater(repo.listCompanies(), throwsA(isA<Offline>()));
      expect(repo.calls, 1);

      repo.failWith = null;
      expect(await repo.listCompanies(), hasLength(2));
      expect(repo.calls, 2);
    });

    test('session repository counts revokes', () async {
      final repo = FakeSessionRepository();
      await repo.revokeCurrentKey();
      expect(repo.revokeCount, 1);
      expect((await repo.me()).companyIds, hasLength(2));
    });

    test('an injected feed replaces the demo feed', () async {
      final repo = FakeInboxRepository()
        ..feed = const AttentionFeed(items: [], totalCount: 0);
      expect((await repo.fetchAttention('x')).items, isEmpty);
    });
  });
}
