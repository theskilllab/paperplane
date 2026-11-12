import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/models/attention.dart';

import '../support/fixtures.dart';

/// Contract test for `GET /companies/{id}/attention`.
///
/// `attention_feed.json` holds a payload recorded from a real Paperclip
/// instance and then scrubbed (see the fixture README). It is parsed with the
/// same models the app uses, so a server change that breaks the app fails
/// here rather than on a phone.
void main() {
  group('recorded /attention payload', () {
    final json = loadFixtureMap('attention_feed.json');
    final feed = AttentionFeed.fromJson(json);

    test('feed fields parse', () {
      expect(feed.items, hasLength(2));
      expect(feed.totalCount, 2);
      expect(feed.generatedAt, DateTime.utc(2026, 11, 7, 10));
      expect(feed.nextCursor, isNull);
      expect(feed.isTruncated, isFalse);
      expect(feed.countsBySourceKind, hasLength(11));
      expect(feed.countsBySourceKind['approval'], 1);
      expect(feed.countsBySourceKind['blocker_attention'], 1);
    });

    test('every recorded item keeps the fields the app reads', () {
      for (final item in json['items']! as List<Object?>) {
        expect(
          item,
          containsPair('sourceKind', isA<String>()),
          reason: 'sourceKind',
        );
        final map = (item! as Map).cast<String, Object?>();
        expect(map, contains('subject'), reason: 'subject');
        expect(map, contains('activityAt'), reason: 'activityAt');
        expect(map, contains('inlineResolvable'), reason: 'inlineResolvable');
        expect(map, contains('rank'), reason: 'rank');
      }
    });

    test('the approval row parses', () {
      final approval = feed.items.first;
      expect(approval.id, 'item-recorded-1');
      expect(approval.sourceKind, SourceKind.approval);
      expect(approval.title, 'Approve the recorded example');
      expect(approval.subject.href, '/REC/approvals/approval-recorded-1');
      expect(approval.activityAt, DateTime.utc(2026, 11, 7, 9, 58));
      expect(approval.inlineResolvable, isFalse);
      expect(approval.requestedByAgentId, isNull);
      expect(approval.sourceKind.group, InboxGroup.approvals);
    });

    test('the blocker row parses', () {
      final blocker = feed.items.last;
      expect(blocker.id, 'item-recorded-2');
      expect(blocker.sourceKind, SourceKind.blockerAttention);
      expect(blocker.title, 'Issue blocked on a recorded example');
      expect(blocker.subject.href, '/REC/issues/REC-2');
      expect(blocker.subject.metadata['priority'], 'low');
      expect(blocker.sourceKind.group, InboxGroup.needsAttention);
    });
  });
}
