import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/api/models/health.dart';
import 'package:paperplane/api/models/session_info.dart';
import 'package:paperplane/data/fake/demo_data.dart';

import '../support/fixtures.dart';

void main() {
  group('AttentionFeed', () {
    final feed = AttentionFeed.fromJson(
      demoAttentionJson(DateTime.utc(2026, 1, 15, 12)),
    );

    test('parses every item of the fixture', () {
      expect(feed.items, hasLength(13));
      expect(feed.totalCount, 13);
      expect(feed.isTruncated, isFalse);
      expect(feed.generatedAt, DateTime.utc(2026, 1, 15, 12));
      expect(feed.nextCursor, isNull);
    });

    test('covers all 11 known sourceKinds and one unknown', () {
      final known = {
        for (final item in feed.items)
          if (item.sourceKind != SourceKind.unknown) item.sourceKind,
      };
      expect(
        known,
        SourceKind.values.where((k) => k != SourceKind.unknown).toSet(),
      );
      expect(known, hasLength(11));
      final unknown = feed.items.singleWhere(
        (i) => i.sourceKind == SourceKind.unknown,
      );
      expect(unknown.rawSourceKind, 'a_kind_from_a_newer_server');
    });

    test('counts per kind match the items', () {
      expect(feed.countsBySourceKind['approval'], 2);
      expect(feed.countsBySourceKind['failed_run'], 1);
      expect(
        feed.countsBySourceKind.values.fold<int>(0, (a, b) => a + b),
        feed.items.length,
      );
    });

    test('groups into Approvals, Questions and Needs attention', () {
      expect(feed.inGroup(InboxGroup.approvals), hasLength(2));
      expect(feed.inGroup(InboxGroup.questions), hasLength(1));
      expect(feed.inGroup(InboxGroup.needsAttention), hasLength(10));
    });

    test('reads approval details', () {
      final approval = feed.items.first;
      expect(approval.sourceKind, SourceKind.approval);
      expect(approval.title, 'Hire a support agent');
      expect(approval.inlineResolvable, isTrue);
      expect(approval.requestedByAgentId, 'agent-ceo');
      expect(approval.subject.href, '/ACM/approvals/appr-01');
      expect(approval.resolverAudience, 'board');
    });

    test('an item without href is not tappable', () {
      final errorAlert = feed.items.singleWhere(
        (i) => i.sourceKind == SourceKind.agentErrorAlert,
      );
      expect(errorAlert.subject.href, isNull);
    });

    test('reports truncation when the server has more items', () {
      final truncated = AttentionFeed.fromJson(const {
        'items': [
          {'id': 'a', 'sourceKind': 'approval', 'title': 't'},
        ],
        'totalCount': 250,
        'nextCursor': 'abc',
      });
      expect(truncated.isTruncated, isTrue);
      expect(truncated.nextCursor, 'abc');
    });
  });

  group('tolerant parsing', () {
    test('garbage never throws', () {
      for (final junk in <Object?>[
        null,
        42,
        'text',
        <Object?>[],
        {'items': 'nope', 'totalCount': 'x', 'countsBySourceKind': <Object?>[]},
        {
          'items': [1, null, 'a', <String, Object?>{}],
        },
      ]) {
        final map = junk is Map
            ? Map<String, Object?>.from(junk)
            : <String, Object?>{};
        expect(() => AttentionFeed.fromJson(map), returnsNormally);
      }
      expect(
        AttentionFeed.fromJson(const {}).items,
        isEmpty,
        reason: 'missing items read as empty',
      );
    });

    test('an item with wrong field types still parses', () {
      final item = AttentionItem.fromJson(const {
        'id': 7,
        'sourceKind': 5,
        'title': null,
        'createdAt': 'not a date',
        'inlineResolvable': 'yes',
        'subject': 'x',
      });
      expect(item.id, '');
      expect(item.sourceKind, SourceKind.unknown);
      expect(item.title, '');
      expect(item.createdAt, isNull);
      expect(item.inlineResolvable, isFalse);
      expect(item.subject.href, isNull);
    });

    test('inlineResolvable defaults to false when absent', () {
      expect(
        AttentionItem.fromJson(const {'id': 'a', 'sourceKind': 'approval'})
            .inlineResolvable,
        isFalse,
      );
    });

    test('title falls back to subject.title', () {
      final item = AttentionItem.fromJson(const {
        'id': 'a',
        'subject': {'title': 'From subject'},
      });
      expect(item.title, 'From subject');
    });

    test('totalCount defaults to the number of items', () {
      final feed = AttentionFeed.fromJson(const {
        'items': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      });
      expect(feed.totalCount, 2);
    });
  });

  group('SourceKind', () {
    test('round-trips every known wire value', () {
      for (final kind in SourceKind.values) {
        if (kind == SourceKind.unknown) continue;
        expect(SourceKind.parse(kind.wire), kind);
      }
      expect(SourceKind.parse(null), SourceKind.unknown);
      expect(SourceKind.parse(''), SourceKind.unknown);
    });
  });

  group('Company', () {
    test('parses the list and drops entries without an id', () {
      final companies = Company.listFromJson([
        ...(loadFixture('companies.json')! as List<Object?>),
        {'name': 'No id'},
        'junk',
      ]);
      expect(companies.map((c) => c.name), ['Acme Demo', 'Globex Demo']);
      expect(companies.first.issuePrefix, 'ACM');
    });

    test('non-list input is an empty list', () {
      expect(Company.listFromJson({'a': 1}), isEmpty);
    });
  });

  group('HealthInfo', () {
    test('parses authenticated mode', () {
      final health = HealthInfo.fromJson(loadFixtureMap('health.json'));
      expect(health.isHealthy, isTrue);
      expect(health.mode, DeploymentMode.authenticated);
      expect(health.exposure, 'private');
      expect(health.version, isNull);
    });

    test('knows local_trusted and tolerates new modes', () {
      expect(
        DeploymentMode.parse('local_trusted'),
        DeploymentMode.localTrusted,
      );
      expect(DeploymentMode.parse('something_new'), DeploymentMode.unknown);
      expect(HealthInfo.fromJson(const {}).isHealthy, isFalse);
    });
  });

  group('SessionInfo', () {
    test('parses /cli-auth/me', () {
      final me = SessionInfo.fromJson(loadFixtureMap('session_me.json'));
      expect(me.userId, 'user-demo-1');
      expect(me.keyId, 'key-demo-1');
      expect(me.companyIds, ['company-demo-1', 'company-demo-2']);
      expect(me.userEmail, 'demo@example.invalid');
    });

    test('missing fields do not throw', () {
      final me = SessionInfo.fromJson(const {});
      expect(me.userId, '');
      expect(me.companyIds, isEmpty);
    });
  });
}
