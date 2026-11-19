import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/approval.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/features/approvals/approval_screen.dart';
import 'package:paperplane/features/inbox/inbox_controller.dart';

import '../inbox/inbox_harness.dart' show testNow;
import 'approval_harness.dart';

Approval demoPending() =>
    Approval.fromJson(demoApprovalJson('appr-01', testNow));

void main() {
  group('S4 AC1: detail', () {
    testWidgets('shows requester, age, title, body and linked issue', (
      tester,
    ) async {
      await pumpApproval(tester);

      expect(find.text('Requested by Chief Example'), findsOneWidget);
      expect(find.text('· 12 min ago'), findsOneWidget);
      expect(find.text('Hire a support agent'), findsOneWidget);
      expect(find.textContaining('Reads support tickets'), findsOneWidget);
      expect(find.text('LINKED ISSUE'), findsOneWidget);
      expect(find.text('ACM-12'), findsOneWidget);
      expect(
        find.text('Add a support agent that reads tickets'),
        findsOneWidget,
      );
    });

    testWidgets('the generic payload card shows the scalar facts', (
      tester,
    ) async {
      await pumpApproval(tester);

      expect(find.text('Role'), findsOneWidget);
      expect(find.text('support'), findsOneWidget);
      expect(find.text('Budget monthly cents'), findsOneWidget);
      expect(find.text(r'$0.00'), findsOneWidget);
      // Internal adapter configuration is not rendered.
      expect(find.textContaining('/example/agent'), findsNothing);
    });
  });

  group('S4 AC2–AC4: decisions', () {
    testWidgets('a pending inline approval shows Approve and Reject', (
      tester,
    ) async {
      await pumpApproval(tester);

      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('Approve sends one request and returns to S2 without the row', (
      tester,
    ) async {
      final h = await pumpApproval(tester);
      // S2 keeps this provider alive under the pushed screen.
      final sub = h.container.listen(
        inboxProvider(demoCompanyId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await h.container.read(inboxProvider(demoCompanyId).future);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(h.approvals.approveCalls, 1);
      expect(h.approvals.rejectCalls, 0);
      expect(find.byType(ApprovalScreen), findsNothing);
      final feed = h.container.read(inboxProvider(demoCompanyId)).value!.feed;
      expect(feed.items.where((item) => item.id == 'att-01'), isEmpty);
    });

    testWidgets('Reject opens the note first and sends it', (tester) async {
      final h = await pumpApproval(tester);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(
        find.text("Reject this request? This can't be undone."),
        findsOneWidget,
      );
      expect(find.text('Rejection note (optional)'), findsOneWidget);
      expect(find.text('Send rejection'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Needs more detail');
      await tester.tap(find.text('Send rejection'));
      await tester.pumpAndSettle();

      expect(h.approvals.rejectCalls, 1);
      expect(h.approvals.lastDecisionNote, 'Needs more detail');
      expect(find.byType(ApprovalScreen), findsNothing);
    });

    testWidgets('Cancel leaves the approval pending and clears the note', (
      tester,
    ) async {
      final h = await pumpApproval(tester);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Draft');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Approve'), findsOneWidget);
      expect(h.approvals.rejectCalls, 0);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('one tap is one request while the button is busy (G6)', (
      tester,
    ) async {
      final h = await pumpApproval(tester);
      h.approvals.latency = const Duration(seconds: 1);

      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.tap(find.text('Approve'), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(h.approvals.approveCalls, 1);
    });
  });

  group('S4 AC5: failure states', () {
    testWidgets('already handled (422) reloads and shows the current state', (
      tester,
    ) async {
      final now = testNow;
      final decided = demoPending().copyWith(
        status: ApprovalStatus.approved,
        decidedAt: now,
        decidedByUserId: 'user-demo-1',
      );
      final repo = _ConflictRepo(decided);
      await pumpApproval(tester, approvals: repo);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Already handled'), findsOneWidget);
      expect(find.textContaining('Approved by you'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(repo.fetchCalls, 2);
    });

    testWidgets('a 403 on a write shows the server message and keeps buttons', (
      tester,
    ) async {
      final h = await pumpApproval(tester);
      h.approvals.decisionError = const Forbidden(
        'Only board users can decide',
      );

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text("You can't do that"), findsOneWidget);
      expect(find.text('Only board users can decide'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(h.approvals.approveCalls, 0);
    });

    testWidgets('offline keeps the typed note and sends nothing', (
      tester,
    ) async {
      final h = await pumpApproval(tester);
      h.approvals.decisionError = const Offline();

      await tester.scrollUntilVisible(
        find.text('Add a comment (optional)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Add a comment (optional)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Please check');
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Can't reach"), findsOneWidget);
      expect(find.text('Please check'), findsOneWidget);
      expect(h.approvals.approveCalls, 0);
    });

    testWidgets('a 5xx on a write shows the status and Retry resends', (
      tester,
    ) async {
      final h = await pumpApproval(tester);
      h.approvals.decisionError = const Server(502);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.textContaining('Error 502'), findsOneWidget);
      expect(h.approvals.approveCalls, 0);

      h.approvals.decisionError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(h.approvals.approveCalls, 1);
    });

    testWidgets('a 404 on a write explains and keeps the buttons, no Retry', (
      tester,
    ) async {
      final h = await pumpApproval(tester);
      h.approvals.decisionError = const NotFound();

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Not found'), findsOneWidget);
      expect(find.text('This item no longer exists.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(h.approvals.approveCalls, 0);
    });
  });

  group('S4 AC7–AC9: body, unknown types and the inline gate', () {
    testWidgets('a very long body scrolls and the bar stays reachable', (
      tester,
    ) async {
      final long = demoPending();
      final h = await pumpApproval(
        tester,
        approvals: FakeApprovalRepository(now: () => testNow)
          ..approval = Approval(
            id: long.id,
            type: long.type,
            status: long.status,
            payload: {
              'title': long.title,
              'description': List.filled(80, 'A long paragraph.').join('\n\n'),
            },
            requestedByAgentId: long.requestedByAgentId,
            createdAt: long.createdAt,
          ),
        size: const Size(360, 640),
        textScale: 2,
      );

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(h.approvals.fetchCalls, 1);
    });

    testWidgets('an unknown type shows the summary and the fallback link, '
        'and still decides', (tester) async {
      final h = await pumpApproval(
        tester,
        demo: false,
        approvals: FakeApprovalRepository(now: () => testNow)
          ..approval = Approval(
            id: 'appr-01',
            type: 'future_approval',
            status: ApprovalStatus.pending,
            payload: const {'summary': 'A request from a newer server.'},
            requestedByAgentId: 'agent-ceo',
            createdAt: testNow,
          ),
      );

      expect(
        find.text('Requests a new agent with read access to tickets.'),
        findsOneWidget,
      );
      expect(find.text('Open in Paperclip'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);

      await tester.tap(find.text('Open in Paperclip'));
      await tester.pump();
      expect(
        h.opened.single.toString(),
        'https://x.example.test/ACM/approvals/appr-01',
      );
    });

    testWidgets('the linked issue opens its Paperclip page', (tester) async {
      final h = await pumpApproval(tester, demo: false);

      await tester.tap(find.text('ACM-12'));
      await tester.pump();

      expect(
        h.opened.single.toString(),
        'https://x.example.test/ACM/issues/ACM-12',
      );
    });

    testWidgets('demo mode explains instead of opening a made-up address', (
      tester,
    ) async {
      final h = await pumpApproval(tester);

      await tester.tap(find.text('ACM-12'));
      await tester.pump();

      expect(h.opened, isEmpty);
      expect(find.textContaining('Demo mode'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('inlineResolvable false is read-only with the summary', (
      tester,
    ) async {
      await pumpApproval(
        tester,
        attention: demoApprovalItem(inlineResolvable: false),
      );

      expect(
        find.text('This request can only be decided in Paperclip.'),
        findsOneWidget,
      );
      expect(
        find.text('Requests a new agent with read access to tickets.'),
        findsOneWidget,
      );
      expect(find.text('Open in Paperclip'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('a decided approval shows who and when, with no actions', (
      tester,
    ) async {
      await pumpApproval(
        tester,
        approvals: FakeApprovalRepository(now: () => testNow)
          ..approval = demoPending().copyWith(
            status: ApprovalStatus.approved,
            decidedAt: testNow,
            decidedByUserId: 'user-demo-1',
          ),
      );

      expect(find.textContaining('Approved by you on'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('another decider reads as "another board user"', (
      tester,
    ) async {
      await pumpApproval(
        tester,
        approvals: FakeApprovalRepository(now: () => testNow)
          ..approval = demoPending().copyWith(
            status: ApprovalStatus.rejected,
            decidedAt: testNow,
            decidedByUserId: 'user-other',
          ),
      );

      expect(
        find.textContaining('Rejected by another board user on'),
        findsOneWidget,
      );
    });
  });
}

/// First fetch pending, second fetch decided: the G10 re-read.
class _ConflictRepo extends FakeApprovalRepository {
  new(this._decided) : super(now: () => testNow);

  final Approval _decided;

  @override
  Future<Approval> fetch(String approvalId) async {
    await simulate();
    fetchCalls++;
    return fetchCalls == 1 ? demoPending() : _decided;
  }

  @override
  Future<Approval> approve(String approvalId, {String? decisionNote}) async {
    await simulate();
    throw const AlreadyHandled(422);
  }
}
