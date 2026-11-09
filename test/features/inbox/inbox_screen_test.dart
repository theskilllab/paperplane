import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/app/router.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/features/inbox/inbox_screen.dart';
import 'package:paperplane/ui/ui.dart';

import 'inbox_harness.dart';

AttentionFeed feedOf(Map<String, Object?> json) => AttentionFeed.fromJson(json);

double top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  group('S2 AC1: one grouped feed', () {
    testWidgets('loads the feed once and groups it in the stated order', (
      tester,
    ) async {
      final h = await pumpInbox(tester);

      expect(h.inbox.feedCalls, 1);
      expect(top(tester, 'APPROVALS'), lessThan(top(tester, 'QUESTIONS')));
      expect(
        top(tester, 'QUESTIONS'),
        lessThan(top(tester, 'NEEDS ATTENTION')),
      );
      expect(find.text('Hire a support agent'), findsOneWidget);
      expect(find.text('Which release channel should we use?'), findsOneWidget);
    });

    testWidgets('the header shows the server total and each group its count', (
      tester,
    ) async {
      await pumpInbox(
        tester,
        inbox: TrackingInbox()
          ..feed = feedOf(demoTruncatedAttentionJson(testNow)),
      );

      // totalCount 137 (not the six rows in hand); approvals 41, questions 23.
      expect(find.text('137'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
      expect(find.text('23'), findsOneWidget);
      // Needs attention = total - approvals - questions.
      expect(find.text('73'), findsOneWidget);
    });

    testWidgets('a row shows icon, title, agent and age', (tester) async {
      await pumpInbox(tester);

      // Approvals carry only an agent id; the name comes from the agent list.
      expect(find.text('Chief Example'), findsWidgets);
      expect(find.text('12 min ago'), findsOneWidget);
      expect(find.byType(AppGhostAvatar), findsWidgets);
    });

    testWidgets('rows read as one spoken sentence', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpInbox(tester);

      expect(
        find.bySemanticsLabel(
          'Approval, Hire a support agent, from Chief Example, 12 min ago, '
          'Opens in your browser',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('an unknown kind is a generic row and does not crash', (
      tester,
    ) async {
      await pumpInbox(tester);

      await tester.scrollUntilVisible(
        find.text('Something this app version does not know'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Something this app version does not know'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Needs attention rows name their own kind', (tester) async {
      await pumpInbox(tester);

      await tester.scrollUntilVisible(
        find.text('Run failed: build step exited with code 1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Failed run'), findsOneWidget);
    });
  });

  group('S2 AC7: rows open the web page', () {
    testWidgets('a row with an href opens base URL + href in the browser', (
      tester,
    ) async {
      final h = await pumpInbox(tester);

      await tester.tap(find.text('Hire a support agent'));
      await tester.pump();

      expect(h.opened, [
        Uri.parse('https://x.example.test/ACM/approvals/appr-01'),
      ]);
    });

    testWidgets('the fragment of a question link is kept', (tester) async {
      final h = await pumpInbox(tester);

      await tester.tap(find.text('Which release channel should we use?'));
      await tester.pump();

      expect(
        h.opened.single.toString(),
        'https://x.example.test/ACM/issues/ACM-12#interaction-int-01',
      );
    });

    testWidgets('a row without an href is not tappable', (tester) async {
      final h = await pumpInbox(tester);

      await tester.scrollUntilVisible(
        find.text('Tester Example reports an error'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Tester Example reports an error'));
      await tester.tap(find.text('Tester Example reports an error'));
      await tester.pump();

      expect(h.opened, isEmpty);
      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('a browser that will not open shows an error toast', (
      tester,
    ) async {
      await pumpInbox(tester, browserOpens: false);

      await tester.tap(find.text('Hire a support agent'));
      await tester.pump();

      expect(find.byType(AppToast), findsOneWidget);
      expect(
        find.text("Couldn't open the page in your browser."),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('demo mode explains instead of opening a made-up address', (
      tester,
    ) async {
      final h = await pumpInbox(tester, demo: true);

      await tester.tap(find.text('Hire a support agent'));
      await tester.pump();

      expect(h.opened, isEmpty);
      expect(find.byType(AppToast), findsOneWidget);
      expect(find.textContaining('Demo mode'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('S2 AC3: states', () {
    testWidgets('first load shows skeleton rows, never a blank screen', (
      tester,
    ) async {
      final inbox = TrackingInbox()..latency = const Duration(seconds: 1);
      await pumpInbox(tester, inbox: inbox, settle: false);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AppSkeletonRow), findsWidgets);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(AppSkeletonRow), findsNothing);
      expect(find.text('Hire a support agent'), findsOneWidget);
    });

    testWidgets('empty: "Nothing needs you" with the last-updated time', (
      tester,
    ) async {
      final inbox = TrackingInbox()
        ..feed = feedOf(demoEmptyAttentionJson(testNow));
      await pumpInbox(tester, inbox: inbox);

      expect(find.text('Nothing needs you'), findsOneWidget);
      expect(
        find.textContaining('Last updated ${formatClock(testNow)}'),
        findsOneWidget,
      );
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('error without data: full-screen state, then Retry works', (
      tester,
    ) async {
      final inbox = TrackingInbox()..failWith = const Offline();
      await pumpInbox(tester, inbox: inbox);

      expect(find.text("Can't reach x.example.test"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Sign out stays reachable.
      expect(find.text('Sign out'), findsOneWidget);

      inbox.failWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Hire a support agent'), findsOneWidget);
    });

    testWidgets('a 5xx shows "Something went wrong" with the status', (
      tester,
    ) async {
      final inbox = TrackingInbox()..failWith = const Server(502);
      await pumpInbox(tester, inbox: inbox);

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Error 502'), findsOneWidget);
    });

    testWidgets('error with data keeps the list and shows a banner', (
      tester,
    ) async {
      final h = await pumpInbox(tester);

      h.inbox.failWith = const Offline();
      await tester.pump(inboxPollInterval);
      await tester.pumpAndSettle();

      expect(find.text('Hire a support agent'), findsOneWidget);
      expect(find.byType(AppBanner), findsOneWidget);
      expect(
        find.textContaining('Last updated ${formatClock(testNow)}'),
        findsOneWidget,
      );

      // It recovers on the next poll and the banner goes away.
      h.inbox.failWith = null;
      await tester.pump(inboxPollInterval);
      await tester.pumpAndSettle();
      expect(find.byType(AppBanner), findsNothing);
    });

    testWidgets('403 shows "no access", and the switcher stays usable', (
      tester,
    ) async {
      final inbox = TrackingInbox()..failWith = const Forbidden('');
      await pumpInbox(tester, inbox: inbox);

      expect(find.text("You don't have access to this"), findsOneWidget);
      expect(find.text('Acme Demo'), findsOneWidget);

      await tester.tap(find.text('Acme Demo'));
      await tester.pumpAndSettle();
      expect(find.text('Switch company'), findsOneWidget);
      expect(find.text('Globex Demo'), findsOneWidget);
    });

    testWidgets('a 401 shows "session expired" and leaves for S1', (
      tester,
    ) async {
      final inbox = TrackingInbox()..failWith = const Unauthorized();
      await pumpInbox(tester, inbox: inbox);

      expect(find.text('Your session expired'), findsOneWidget);
    });

    testWidgets('no companies: says so', (tester) async {
      final companies = FakeCompanyRepository()..companies = [];
      await pumpInbox(tester, companies: companies);

      expect(find.text('No company'), findsOneWidget);
    });

    testWidgets('companies that cannot load: error with Retry', (tester) async {
      final companies = FakeCompanyRepository()..failWith = const Offline();
      await pumpInbox(tester, companies: companies);

      expect(find.text("Can't reach x.example.test"), findsOneWidget);
      companies.failWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Hire a support agent'), findsOneWidget);
    });

    testWidgets('plain http shows the "Not encrypted" banner', (tester) async {
      await pumpInbox(tester, baseUrl: Uri.parse('http://192.168.1.20:3100'));

      expect(find.text('Not encrypted'), findsOneWidget);
    });

    testWidgets('https does not', (tester) async {
      await pumpInbox(tester);
      expect(find.text('Not encrypted'), findsNothing);
    });
  });

  group('S2 AC8: the cap is stated', () {
    testWidgets('"Showing first N of M" when the server has more', (
      tester,
    ) async {
      final inbox = TrackingInbox()
        ..feed = feedOf(demoTruncatedAttentionJson(testNow));
      await pumpInbox(tester, inbox: inbox);

      await tester.scrollUntilVisible(
        find.text('Showing first 6 of 137'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Showing first 6 of 137'), findsOneWidget);
    });

    testWidgets('no cap text when everything is shown', (tester) async {
      await pumpInbox(tester);
      expect(find.textContaining('Showing first'), findsNothing);
    });
  });

  group('S2 AC2, AC6: refresh and polling', () {
    testWidgets('polls every 30 s while visible', (tester) async {
      final h = await pumpInbox(tester);
      expect(h.inbox.feedCalls, 1);

      await tester.pump(const Duration(seconds: 29));
      expect(h.inbox.feedCalls, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(h.inbox.feedCalls, 2);

      await tester.pump(inboxPollInterval);
      await tester.pumpAndSettle();
      expect(h.inbox.feedCalls, 3);
    });

    testWidgets('requests never overlap', (tester) async {
      final h = await pumpInbox(tester);

      h.inbox.latency = const Duration(seconds: 40);
      await tester.pump(inboxPollInterval); // request 2 starts, takes 40 s
      expect(h.inbox.feedCalls, 2);
      await tester.pump(inboxPollInterval); // t = 60 s: still in flight
      expect(h.inbox.feedCalls, 2);

      await tester.pump(const Duration(seconds: 11)); // answered at t = 70 s
      h.inbox.latency = Duration.zero;
      await tester.pump(inboxPollInterval); // next tick may go
      await tester.pumpAndSettle();
      expect(h.inbox.feedCalls, 3);
    });

    testWidgets('pull-to-refresh reloads', (tester) async {
      final h = await pumpInbox(tester);

      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(h.inbox.feedCalls, 2);
    });

    testWidgets('polling stops in the background and resumes with a refresh', (
      tester,
    ) async {
      final h = await pumpInbox(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 3));
      expect(h.inbox.feedCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.inbox.feedCalls, 2);

      await tester.pump(inboxPollInterval);
      await tester.pumpAndSettle();
      expect(h.inbox.feedCalls, 3);
    });

    testWidgets('polling stops while a detail screen covers the Inbox', (
      tester,
    ) async {
      final h = await pumpInbox(tester);
      final router = h.container.read(routerProvider);

      unawaited(router.push('/issues/ACM-12'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 3));
      expect(h.inbox.feedCalls, 1);

      router.pop();
      await tester.pumpAndSettle();
      expect(h.inbox.feedCalls, 2, reason: 'returning refreshes at once');

      await tester.pump(inboxPollInterval);
      await tester.pumpAndSettle();
      expect(h.inbox.feedCalls, 3);
    });

    testWidgets('a refresh keeps the scroll position and updates the count', (
      tester,
    ) async {
      final h = await pumpInbox(tester);
      final list = find.byType(Scrollable).first;

      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      double offset() => tester.state<ScrollableState>(list).position.pixels;
      final before = offset();
      expect(before, greaterThan(0));

      // One approval gets handled elsewhere: the next poll drops it.
      final json = demoAttentionJson(testNow);
      final items =
          (json['items']! as List<Object?>).cast<Map<String, Object?>>()
            ..removeWhere((i) => i['id'] == 'att-01');
      h.inbox.feed = feedOf({
        ...json,
        'items': items,
        'totalCount': items.length,
        'countsBySourceKind': {
          'approval': 1,
          'issue_thread_interaction': 1,
          'decision': 1,
          'join_request': 1,
          'recovery_action': 1,
          'productivity_review': 1,
          'blocker_attention': 1,
          'review': 1,
          'failed_run': 1,
          'budget_alert': 1,
          'agent_error_alert': 1,
          'a_kind_from_a_newer_server': 1,
        },
      });
      await tester.pump(inboxPollInterval);
      await tester.pumpAndSettle();

      expect(offset(), before);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('the "+" button opens S7', (tester) async {
      await pumpInbox(tester);

      await tester.tap(find.bySemanticsLabel('New issue'));
      await tester.pumpAndSettle();

      expect(find.text('S7 New issue'), findsWidgets);
    });
  });
}
