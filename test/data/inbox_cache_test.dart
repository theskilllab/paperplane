import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/data/company_repository.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/inbox_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_adapter.dart';
import '../support/fixtures.dart';

const _base = 'https://paperclip.example.test';

void main() {
  final now = DateTime.utc(2026, 11, 12, 12);

  Future<AppPrefs> prefs([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    return AppPrefs(await SharedPreferences.getInstance());
  }

  ApiClient client(FakeAdapter adapter) =>
      ApiClient(baseUrl: Uri.parse(_base), adapter: adapter);

  group('Inbox cache', () {
    test(
      'keeps the raw answer and reads it back for the same company',
      () async {
        final adapter = FakeAdapter(
          (o) async => jsonBody(demoAttentionJson(now)),
        );
        final store = await prefs();
        final repo = HttpInboxRepository(
          client(adapter),
          prefs: store,
          now: () => now,
        );

        await repo.fetchAttention(demoCompanyId);
        final cached = repo.cachedFeed(demoCompanyId);

        expect(cached, isNotNull);
        expect(cached!.feed.items, hasLength(13));
        expect(cached.savedAt, now);
        expect(repo.cachedFeed(demoCompanyId2), isNull);
      },
    );

    test('a new repository instance sees the same cache', () async {
      final store = await prefs();
      await HttpInboxRepository(
        client(FakeAdapter((o) async => jsonBody(demoAttentionJson(now)))),
        prefs: store,
        now: () => now,
      ).fetchAttention(demoCompanyId);

      final second = HttpInboxRepository(
        client(FakeAdapter((o) async => throw StateError('no network'))),
        prefs: store,
      );
      expect(second.cachedFeed(demoCompanyId), isNotNull);
    });

    test('corrupt cache reads as nothing', () async {
      final store = await prefs({
        'cached_feed': '{not json',
        'cached_feed_company': demoCompanyId,
        'cached_feed_at': now.millisecondsSinceEpoch,
      });
      final repo = HttpInboxRepository(
        client(FakeAdapter((o) async => jsonBody(<String, Object?>{}))),
        prefs: store,
      );
      expect(repo.cachedFeed(demoCompanyId), isNull);
    });
  });

  group('Company cache', () {
    test('keeps the company list for a cold start', () async {
      final store = await prefs();
      final repo = HttpCompanyRepository(
        client(
          FakeAdapter((o) async => jsonBody(loadFixture('companies.json'))),
        ),
        prefs: store,
      );

      await repo.listCompanies();
      final cached = repo.cachedCompanies();
      expect(cached, isNotNull);
      expect(cached!.map((c) => c.name), ['Acme Demo', 'Globex Demo']);
    });

    test('corrupt cache reads as nothing', () async {
      final store = await prefs({'cached_companies': 'no'});
      final repo = HttpCompanyRepository(
        client(FakeAdapter((o) async => jsonBody(<String, Object?>{}))),
        prefs: store,
      );
      expect(repo.cachedCompanies(), isNull);
    });
  });
}
