import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/inbox_repository.dart';
import 'package:paperplane/ui/ui.dart';

import '../../support/network_status.dart';
import 'inbox_harness.dart';

AttentionFeed _cachedFeed() =>
    AttentionFeed.fromJson(demoAttentionJson(testNow));

CachedFeed _cache() => CachedFeed(
  companyId: demoCompanyId,
  feed: _cachedFeed(),
  savedAt: testNow.subtract(const Duration(minutes: 5)),
);

void main() {
  testWidgets('offline banner appears within 5 s of a cold start offline', (
    tester,
  ) async {
    // The request stays in flight: the banner must not wait for it to fail.
    final hang = Completer<AttentionFeed>();
    addTearDown(() {
      if (!hang.isCompleted) hang.complete(_cachedFeed());
    });
    final inbox = TrackingInbox()
      ..cached = _cache()
      ..onFetch = ((_) => hang.future);
    final network = FakeNetworkStatus(online: false);

    await pumpInbox(tester, inbox: inbox, network: network, settle: false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(find.text('Hire a support agent'), findsOneWidget);
    expect(find.text("Can't reach x.example.test"), findsOneWidget);
    expect(find.byType(AppBanner), findsOneWidget);
  });

  testWidgets('offline banner clears within 5 s of the network returning', (
    tester,
  ) async {
    final inbox = TrackingInbox()
      ..cached = _cache()
      ..failWith = const Offline();
    final network = FakeNetworkStatus(online: false);

    await pumpInbox(tester, inbox: inbox, network: network);
    expect(find.byType(AppBanner), findsOneWidget);
    final before = inbox.feedCalls;

    // Reconnect: the OS reports the change and no 30 s poll is due.
    inbox.failWith = null;
    network.setOnline(online: true);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(inbox.feedCalls, greaterThan(before));
    expect(find.byType(AppBanner), findsNothing);
    expect(find.text('Hire a support agent'), findsOneWidget);
  });

  testWidgets('a request that started offline does not delay recovery', (
    tester,
  ) async {
    final first = Completer<AttentionFeed>();
    var requests = 0;
    final inbox = TrackingInbox()
      ..cached = _cache()
      ..onFetch = ((_) {
        requests++;
        return requests == 1 ? first.future : Future.value(_cachedFeed());
      });
    final network = FakeNetworkStatus(online: false);

    await pumpInbox(tester, inbox: inbox, network: network, settle: false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(AppBanner), findsOneWidget);

    // Reconnect while the first request is still in flight.
    network.setOnline(online: true);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(inbox.feedCalls, 2);
    expect(find.byType(AppBanner), findsNothing);

    // The old request fails after the reconnect; its answer is not newer.
    first.completeError(const Offline());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(AppBanner), findsNothing);
    expect(find.text('Hire a support agent'), findsOneWidget);
  });
}
