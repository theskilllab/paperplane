import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/app/routes.dart';
import 'package:paperplane/features/inbox/inbox_target.dart';

import '../../support/fixtures.dart';

AttentionItem item(
  SourceKind kind, {
  String id = 'att-1',
  String? href,
  bool inline = true,
}) => AttentionItem(
  id: id,
  sourceKind: kind,
  title: 'Title',
  subject: AttentionSubject(href: href),
  inlineResolvable: inline,
);

void main() {
  final base = Uri.parse('https://x.example.test');

  test('an approval opens S4 with the approval id from its href', () {
    final target = itemTarget(
      item(SourceKind.approval, href: '/ACM/approvals/appr-01'),
      baseUrl: base,
    );

    expect(target, isA<AttentionRoute>());
    final route = target! as AttentionRoute;
    expect(route.location, AppRoutes.approval('appr-01'));
    expect(route.item.id, 'att-1');
  });

  test('an approval without a usable href is not tappable', () {
    for (final href in [null, '', 'https://evil.example.test/x', '//x/y']) {
      expect(
        itemTarget(item(SourceKind.approval, href: href), baseUrl: base),
        isNull,
        reason: '$href',
      );
    }
  });

  test('other kinds keep the browser stopgap', () {
    final target = itemTarget(
      item(SourceKind.issueThreadInteraction, href: '/ACM/issues/ACM-12#i'),
      baseUrl: base,
    );

    expect(target, isA<AttentionBrowser>());
    expect(
      (target! as AttentionBrowser).url.toString(),
      'https://x.example.test/ACM/issues/ACM-12#i',
    );
  });

  test('the recorded approval row uses the id in its href, not the row id', () {
    final feed = AttentionFeed.fromJson(loadFixtureMap('attention_feed.json'));
    final target = itemTarget(feed.items.first, baseUrl: base);

    expect(target, isA<AttentionRoute>());
    final route = target! as AttentionRoute;
    expect(route.location, AppRoutes.approval('approval-recorded-1'));
    expect(route.item.id, 'item-recorded-1');
  });

  test('an approval with no href and no id is not tappable', () {
    expect(
      itemTarget(item(SourceKind.approval, id: ''), baseUrl: base),
      isNull,
    );
  });
}
