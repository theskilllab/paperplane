import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/issue.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/features/issues/issue_thread.dart';
import 'package:paperplane/ui/ui.dart';

import 'issue_harness.dart';

Finder sendButton() => find.bySemanticsLabel('Send reply');
Finder field() => find.byType(TextField);

bool sendEnabled(WidgetTester tester) =>
    tester
        .getSemantics(sendButton())
        .getSemanticsData()
        .flagsCollection
        .isEnabled
        .toBoolOrNull() ??
    false;

ScrollPosition threadPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// The thread opens at its latest comment; scroll up to the header.
Future<void> jumpToTop(WidgetTester tester) async {
  final position = threadPosition(tester);
  position.jumpTo(position.minScrollExtent);
  await tester.pump();
}

Future<void> pullToRefresh(WidgetTester tester) async {
  await tester.drag(
    find.byType(SingleChildScrollView).first,
    const Offset(0, 300),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

/// True when [finder] is drawn inside the thread area (below the bar, above
/// the reply field). The thread is one laid-out column, so a widget that is
/// scrolled away still exists; this tells the two apart.
bool onScreen(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final rect = tester.getRect(finder.first);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.top >= 52 && rect.bottom <= screen.height - 60;
}

void main() {
  group('S6 header, description and thread (AC1, AC2, AC9)', () {
    testWidgets(
      'opens scrolled to the latest comment; header and description are above',
      (tester) async {
        final h = await pumpIssue(tester);

        // AC1: the view starts at the newest comment.
        expect(onScreen(tester, find.textContaining('(#5)')), isTrue);
        expect(onScreen(tester, find.text('Update the pricing page')), isFalse);
        expect(
          threadPosition(tester).pixels,
          threadPosition(tester).maxScrollExtent,
        );

        await jumpToTop(tester);
        expect(find.text('ACM-12'), findsOneWidget); // nav bar
        expect(onScreen(tester, find.text('Update the pricing page')), isTrue);
        expect(find.text('In progress'), findsOneWidget);
        expect(find.text('Assignee: Engineer Example'), findsOneWidget);
        expect(find.text('Project: Website'), findsOneWidget);
        // Markdown description: heading, list item, and an image placeholder.
        expect(find.text('Goal'), findsOneWidget);
        expect(find.text('Update the table'), findsOneWidget);
        expect(find.textContaining('Image: mockup'), findsOneWidget);
        // AC9: opening wrote nothing.
        expect(h.issues.postedBodies, isEmpty);
      },
    );

    testWidgets('agent and human comments are told apart', (tester) async {
      await pumpIssue(tester);
      // Agent comments: name, an "Agent" pill. Own comments: "You".
      expect(find.text('Engineer Example'), findsWidgets);
      expect(find.text('Agent'), findsWidgets);
      expect(find.text('You'), findsWidgets);
    });

    testWidgets('an agent mention in a body reads as @Name, not a raw link', (
      tester,
    ) async {
      await pumpIssue(tester);
      expect(find.textContaining('agent://'), findsNothing);
      expect(find.textContaining('@Tester Example'), findsOneWidget);
    });

    testWidgets('opens at the latest comment of a long thread', (tester) async {
      await pumpIssue(tester, issueId: 'GLX-4');
      final latest = find.textContaining('(#129)');
      expect(latest, findsOneWidget);
      final rect = tester.getRect(latest);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(rect.bottom, lessThan(screen.height));
      expect(rect.top, greaterThan(0));
      // The description is far above.
      expect(
        onScreen(tester, find.text('Review the quarterly numbers')),
        isFalse,
      );
    });

    testWidgets('links open in the browser; images are placeholders', (
      tester,
    ) async {
      final h = await pumpIssue(tester);
      await jumpToTop(tester);
      await tester.tapOnText(find.textRange.ofSubstring('style guide').first);
      await tester.pump();
      expect(h.opened, [Uri.parse('https://docs.example.test/style')]);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a thread with no comments says so', (tester) async {
      final repo = GatedIssueRepository()
        ..issue = const Issue(
          id: 'i',
          identifier: 'ACM-1',
          title: 'Empty one',
          status: IssueStatus.todo,
        )
        ..thread = [];
      await pumpIssue(tester, issues: repo);
      expect(find.text('No comments yet.'), findsOneWidget);
      expect(find.text('No description.'), findsOneWidget);
    });
  });

  group('paging (AC3)', () {
    testWidgets('Load earlier adds older comments and keeps the view still', (
      tester,
    ) async {
      final h = await pumpIssue(tester, issueId: 'GLX-4');
      // 130 comments: the newest 50 are loaded, #80 is the oldest of them.
      await jumpToTop(tester);
      final anchor = find.textContaining('#80');
      expect(onScreen(tester, anchor), isTrue);
      final before = tester.getTopLeft(anchor).dy;

      final fetches = h.issues.commentFetches;
      await tester.tap(find.text('Load earlier'));
      await tester.pumpAndSettle();

      expect(h.issues.commentFetches, fetches + 1);
      final state = h.container.read(issueThreadProvider('GLX-4'));
      expect(state.comments, hasLength(100));
      expect(state.comments.first.id, 'c-glx-4-030');
      expect(state.hasEarlier, isTrue); // 30 more
      // What the user was reading did not move.
      expect(tester.getTopLeft(anchor).dy, closeTo(before, 2));
      // The older comments are above it.
      expect(find.textContaining('#79'), findsOneWidget);
      expect(
        tester.getTopLeft(find.textContaining('#79')).dy,
        lessThan(before),
      );
    });

    testWidgets('the Load earlier button is gone when nothing is earlier', (
      tester,
    ) async {
      await pumpIssue(tester);
      expect(find.text('Load earlier'), findsNothing);
    });
  });

  group('reply (AC4, AC5, AC6)', () {
    testWidgets('empty and whitespace-only cannot be sent', (tester) async {
      final h = await pumpIssue(tester);
      expect(sendEnabled(tester), isFalse);

      await tester.enterText(field(), '   \n ');
      await tester.pump();
      expect(sendEnabled(tester), isFalse);
      await tester.tap(sendButton(), warnIfMissed: false);
      await tester.pump();
      expect(h.issues.postedBodies, isEmpty);

      await tester.enterText(field(), 'Hi');
      await tester.pump();
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('sending shows the comment at once, then confirms', (
      tester,
    ) async {
      final h = await pumpIssue(tester);
      await tester.enterText(field(), 'Looks good, merge it');
      await tester.pump();
      h.issues.latency = const Duration(seconds: 1);

      await tester.tap(sendButton());
      await tester.pump();
      // Pending: in the thread, marked sending, composer cleared and locked.
      expect(find.text('Looks good, merge it'), findsOneWidget);
      expect(find.text('Sending…'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      expect(sendEnabled(tester), isFalse);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Sending…'), findsNothing);
      expect(find.text('Looks good, merge it'), findsOneWidget);
      expect(h.issues.postedBodies, ['Looks good, merge it']);
    });

    testWidgets('one tap sends one request even if tapped twice', (
      tester,
    ) async {
      final h = await pumpIssue(tester);
      await tester.enterText(field(), 'Once');
      await tester.pump();
      h.issues.latency = const Duration(seconds: 1);

      await tester.tap(sendButton());
      await tester.pump();
      await tester.tap(sendButton(), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(h.issues.postedBodies, ['Once']);
    });

    testWidgets('the @agent button opens a sheet and inserts the mention', (
      tester,
    ) async {
      final h = await pumpIssue(tester);
      await tester.enterText(field(), 'Please check');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Mention an agent'));
      await tester.pumpAndSettle();
      expect(find.text('Mention an agent'), findsWidgets);
      expect(find.text('Tester Example'), findsWidgets);
      await tester.tap(find.text('Tester Example').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(field()).controller!.text,
        'Please check @Tester Example ',
      );
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(h.issues.postedBodies, [
        'Please check [@Tester Example](agent://agent-qa)',
      ]);
    });

    testWidgets('dismissing the agent sheet changes nothing', (tester) async {
      await pumpIssue(tester);
      await tester.enterText(field(), 'Hi');
      await tester.tap(find.bySemanticsLabel('Mention an agent'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field()).controller!.text, 'Hi');
    });

    testWidgets('failure: "Not sent — Retry" keeps the text; Retry resends', (
      tester,
    ) async {
      final h = await pumpIssue(tester);
      h.issues.failNextPost = const Offline();
      await tester.enterText(field(), 'Do not lose me');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.text('Do not lose me'), findsOneWidget);
      expect(find.text('Not sent — Retry'), findsOneWidget);
      expect(find.textContaining("Can't reach the server"), findsOneWidget);
      expect(h.issues.postedBodies, isEmpty);

      await tester.tap(find.widgetWithText(AppButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Not sent — Retry'), findsNothing);
      expect(h.issues.postedBodies, ['Do not lose me']);
      expect(find.text('Do not lose me'), findsOneWidget);
    });

    testWidgets('Edit puts the text back in the composer', (tester) async {
      final h = await pumpIssue(tester);
      h.issues.failNextPost = const Server(500);
      await tester.enterText(field(), 'First try');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Not sent — Retry'), findsNothing);
      expect(tester.widget<TextField>(field()).controller!.text, 'First try');
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('Edit after a lost answer does not post a second comment', (
      tester,
    ) async {
      final h = await pumpIssue(tester);
      // The server stored the reply before the answer was lost.
      await h.issues.postComment(
        'issue-acm-12',
        body: 'Hello',
        clientRequestId: 'req-1',
      );
      h.issues.failNextPost = const TimedOut();
      await tester.enterText(field(), 'Hello');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(find.text('Not sent — Retry'), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Not sent — Retry'), findsNothing);
      expect(find.textContaining('already sent'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      expect(h.issues.postedBodies, ['Hello']);
      // Let the "already sent" toast timer finish before the test ends.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a failed check warns before Edit drops the reply id', (
      tester,
    ) async {
      final h = await pumpIssue(tester);
      h.issues.failNextPost = const TimedOut();
      await tester.enterText(field(), 'Might be sent');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      h.issues.failWith = const Offline();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Check the thread first'), findsOneWidget);
      expect(find.textContaining('may already be in'), findsOneWidget);

      await tester.tap(find.text('Edit anyway'));
      await tester.pumpAndSettle();
      expect(find.text('Not sent — Retry'), findsNothing);
      expect(
        tester.widget<TextField>(field()).controller!.text,
        'Might be sent',
      );
    });

    testWidgets(
      'a 403 on a reply shows the server message and keeps the text',
      (tester) async {
        final h = await pumpIssue(tester);
        h.issues.failNextPost = const Forbidden('Replies are closed');
        await tester.enterText(field(), 'Hello');
        await tester.pump();
        await tester.tap(sendButton());
        await tester.pumpAndSettle();
        expect(find.textContaining('Replies are closed'), findsOneWidget);
        expect(find.text('Hello'), findsOneWidget);
        expect(find.text('Not sent — Retry'), findsOneWidget);
      },
    );

    testWidgets('a closed issue can be read; the reply bar stays', (
      tester,
    ) async {
      final repo = GatedIssueRepository()
        ..issue = Issue.fromJson({
          ...demoIssueJson('ACM-12'),
          'status': 'done',
        });
      await pumpIssue(tester, issues: repo);
      // The note sits under the last comment, where the view opens.
      expect(find.textContaining('This issue is done'), findsOneWidget);
      expect(field(), findsOneWidget);
      await jumpToTop(tester);
      expect(find.text('Done'), findsOneWidget);
      expect(find.textContaining('Started on this'), findsOneWidget);
    });
  });

  group('refresh and errors (AC7, AC8, G2-G5)', () {
    testWidgets('pull to refresh reads the thread again', (tester) async {
      final h = await pumpIssue(tester);
      final before = h.issues.commentFetches;
      await jumpToTop(tester);
      await pullToRefresh(tester);
      expect(h.issues.commentFetches, before + 1);
    });

    testWidgets('no polling: five minutes pass, nothing is fetched', (
      tester,
    ) async {
      final h = await pumpIssue(tester);
      final before = h.issues.commentFetches;
      await tester.pump(const Duration(minutes: 5));
      expect(h.issues.commentFetches, before);
    });

    testWidgets('404: not found, no retry loop', (tester) async {
      await pumpIssue(tester, issueId: 'NOPE-1');
      expect(find.text('Not found'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('403 on read: no access with a Back action', (tester) async {
      final repo = GatedIssueRepository()..failWith = const Forbidden('');
      await pumpIssue(tester, issues: repo);
      expect(find.text("You don't have access to this"), findsOneWidget);
      expect(find.text('Back'), findsWidgets);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('5xx: something went wrong with Retry and the status', (
      tester,
    ) async {
      final repo = GatedIssueRepository()..failWith = const Server(502);
      await pumpIssue(tester, issues: repo);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Error 502'), findsOneWidget);

      repo.failWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('(#5)'), findsOneWidget);
    });

    testWidgets('offline on open: can’t reach the server with Retry', (
      tester,
    ) async {
      final repo = GatedIssueRepository()..failWith = const Offline();
      await pumpIssue(tester, issues: repo);
      expect(find.textContaining("Can't reach"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
      'offline on refresh keeps the thread and says when it is from',
      (tester) async {
        final h = await pumpIssue(tester);
        h.issues.failWith = const Offline();
        await jumpToTop(tester);
        await pullToRefresh(tester);

        expect(find.textContaining("Can't reach"), findsOneWidget);
        expect(find.textContaining('Last updated'), findsOneWidget);
        expect(find.text('Update the pricing page'), findsOneWidget);

        h.issues.failWith = null;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.textContaining("Can't reach"), findsNothing);
      },
    );

    testWidgets('a first load shows a skeleton, not a blank screen', (
      tester,
    ) async {
      final repo = GatedIssueRepository()..latency = const Duration(seconds: 1);
      await pumpIssue(tester, issues: repo, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('(#5)'), findsOneWidget);
    });
  });

  group('accessibility and layout (G8, G9)', () {
    testWidgets('controls are labelled and at least 44 pt', (tester) async {
      await pumpIssue(tester);
      for (final label in ['Send reply', 'Mention an agent']) {
        final size = tester.getSize(find.bySemanticsLabel(label));
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
      }
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
    });

    testWidgets('failed reply actions are at least 44 pt', (tester) async {
      final h = await pumpIssue(tester);
      h.issues.failNextPost = const Offline();
      await tester.enterText(field(), 'x');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      for (final label in ['Retry', 'Edit']) {
        final size = tester.getSize(find.widgetWithText(AppButton, label));
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
      }
    });

    testWidgets('Dynamic Type XXL: no overflow, actions still reachable', (
      tester,
    ) async {
      final h = await pumpIssue(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      h.issues.failNextPost = const Offline();
      await tester.enterText(field(), 'Big text');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Not sent — Retry'), findsOneWidget);
      for (final label in ['Retry', 'Edit']) {
        final size = tester.getSize(find.widgetWithText(AppButton, label));
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
      }
    });

    testWidgets('iPad: one centered column, no horizontal scroll', (
      tester,
    ) async {
      await pumpIssue(tester, size: const Size(820, 1180));
      expect(tester.takeException(), isNull);
      await jumpToTop(tester);
      final title = tester.getRect(find.text('Update the pricing page'));
      expect(title.width, lessThanOrEqualTo(640));
      expect(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
        findsNothing,
      );
    });
  });
}
