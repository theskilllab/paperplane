import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/features/inbox/inbox_format.dart';

import 'inbox_harness.dart';

void main() {
  group('formatAge', () {
    final now = DateTime.utc(2026, 11, 9, 12);

    test('reads like the prototype', () {
      expect(formatAge(now, now), 'just now');
      expect(
        formatAge(now.subtract(const Duration(seconds: 59)), now),
        'just now',
      );
      expect(
        formatAge(now.subtract(const Duration(minutes: 1)), now),
        '1 min ago',
      );
      expect(
        formatAge(now.subtract(const Duration(minutes: 59)), now),
        '59 min ago',
      );
      expect(formatAge(now.subtract(const Duration(hours: 3)), now), '3 h ago');
      expect(
        formatAge(now.subtract(const Duration(hours: 23)), now),
        '23 h ago',
      );
      expect(formatAge(now.subtract(const Duration(days: 2)), now), '2 d ago');
    });

    test('a time in the future (clock skew) is "just now"', () {
      expect(formatAge(now.add(const Duration(minutes: 5)), now), 'just now');
    });

    test('no time, no text', () => expect(formatAge(null, now), isEmpty));
  });

  group('webUrlFor', () {
    final base = Uri.parse('https://paperclip.example.test');

    test('joins base and href, keeping the fragment', () {
      expect(
        webUrlFor(base, '/ACM/issues/ACM-12#interaction-int-01').toString(),
        'https://paperclip.example.test/ACM/issues/ACM-12#interaction-int-01',
      );
    });

    test('keeps a query and an encoded segment', () {
      expect(
        webUrlFor(base, '/ACM/a%20b?tab=x').toString(),
        'https://paperclip.example.test/ACM/a%20b?tab=x',
      );
    });

    test('keeps a port and a path prefix of the server', () {
      final nested = Uri.parse('http://192.168.1.20:3100/paperclip');
      expect(
        webUrlFor(nested, '/ACM/costs').toString(),
        'http://192.168.1.20:3100/paperclip/ACM/costs',
      );
    });

    test('no href means not tappable', () {
      expect(webUrlFor(base, null), isNull);
      expect(webUrlFor(base, ''), isNull);
    });

    test('never follows an address that points elsewhere', () {
      expect(webUrlFor(base, 'https://evil.example.test/x'), isNull);
      expect(webUrlFor(base, '//evil.example.test/x'), isNull);
      expect(webUrlFor(base, 'javascript:alert(1)'), isNull);
      expect(webUrlFor(base, 'ACM/relative'), isNull);
      expect(webUrlFor(base, 'mailto:a@b.test'), isNull);
    });
  });

  group('groupCount', () {
    test('uses the server counts when the feed is cut', () {
      final feed = AttentionFeed.fromJson(demoTruncatedAttentionJson(testNow));
      expect(groupCount(feed, InboxGroup.approvals), 41);
      expect(groupCount(feed, InboxGroup.questions), 23);
      expect(groupCount(feed, InboxGroup.needsAttention), 137 - 41 - 23);
    });

    test('falls back to the rows in hand without counts', () {
      final feed = AttentionFeed.fromJson({
        ...demoAttentionJson(testNow),
        'countsBySourceKind': const <String, int>{},
      });
      expect(groupCount(feed, InboxGroup.approvals), 2);
      expect(groupCount(feed, InboxGroup.questions), 1);
      expect(groupCount(feed, InboxGroup.needsAttention), 10);
    });

    test('never reports fewer than the rows shown', () {
      final feed = AttentionFeed.fromJson({
        ...demoAttentionJson(testNow),
        'countsBySourceKind': const {'approval': 1},
      });
      expect(groupCount(feed, InboxGroup.approvals), 2);
    });
  });

  group('kinds', () {
    test('every kind has a label and an icon', () {
      for (final kind in SourceKind.values) {
        expect(kindLabel(kind), isNotEmpty);
        kindIcon(kind); // exhaustive switch: compiles and does not throw
      }
    });

    test('groups are named in the order the PRD gives', () {
      expect(InboxGroup.values.map(groupLabel), [
        'Approvals',
        'Questions',
        'Needs attention',
      ]);
    });
  });
}
