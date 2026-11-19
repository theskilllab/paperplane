import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/agent.dart';
import 'package:paperplane/api/models/issue.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/ui/ui.dart';

import '../inbox/inbox_harness.dart';
import 'new_issue_harness.dart';

Finder titleField() => find.byType(TextField).at(0);
Finder descriptionField() => find.byType(TextField).at(1);

AppButton createButton(WidgetTester tester) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, 'Create issue'));

bool createEnabled(WidgetTester tester) =>
    createButton(tester).onPressed != null;

String titleText(WidgetTester tester) =>
    tester.widget<TextField>(titleField()).controller!.text;

String descriptionText(WidgetTester tester) =>
    tester.widget<TextField>(descriptionField()).controller!.text;

String longTitle(int length) => List.filled(length, 'a').join();

/// Agent list held open, so a test can look at the form while it is loading.
class GatedAgents extends FakeAgentRepository {
  /// Completes the pending [listAgents].
  final completer = Completer<List<Agent>>();

  /// Answers the pending call with [agents].
  void complete(List<Agent> agents) => completer.complete(agents);

  @override
  Future<List<Agent>> listAgents(String companyId) => completer.future;
}

void main() {
  testWidgets('the Inbox + button opens S7', (tester) async {
    await pumpInbox(tester);
    await tester.tap(find.bySemanticsLabel('New issue'));
    await tester.pumpAndSettle();

    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Create issue'), findsOneWidget);
  });

  group('S7 fields and defaults (AC1-AC3)', () {
    testWidgets('opens with the title focused and the CEO as assignee', (
      tester,
    ) async {
      await pumpNewIssue(tester);

      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Assignee'), findsOneWidget);
      expect(find.text('Chief Example'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(createEnabled(tester), isFalse);
    });

    testWidgets('no CEO means the default assignee is Unassigned', (
      tester,
    ) async {
      final agents = FakeAgentRepository()
        ..agents = const [
          Agent(id: 'agent-eng', name: 'Engineer Example', role: 'engineer'),
        ];
      await pumpNewIssue(tester, agents: agents);

      expect(find.text('Unassigned'), findsOneWidget);
      expect(find.text('Chief Example'), findsNothing);
    });

    testWidgets('title is required and capped at 200 characters (AC2)', (
      tester,
    ) async {
      await pumpNewIssue(tester);

      await tester.enterText(titleField(), '   ');
      await tester.pump();
      expect(createEnabled(tester), isFalse);

      await tester.enterText(titleField(), longTitle(201));
      await tester.pump();
      expect(
        find.text('Title must be 200 characters or fewer.'),
        findsOneWidget,
      );
      expect(createEnabled(tester), isFalse);

      await tester.enterText(titleField(), longTitle(200));
      await tester.pump();
      expect(find.text('Title must be 200 characters or fewer.'), findsNothing);
      expect(createEnabled(tester), isTrue);
    });

    testWidgets('Create waits until the CEO default is resolved (AC1, AC3)', (
      tester,
    ) async {
      final agents = GatedAgents();
      final h = await pumpNewIssue(tester, agents: agents);

      await tester.enterText(titleField(), 'Wait for the CEO');
      await tester.pump();
      expect(find.text('Loading…'), findsOneWidget);
      expect(createEnabled(tester), isFalse);

      await tester.tap(find.text('Create issue'), warnIfMissed: false);
      await tester.pump();
      expect(h.issues.createCalls, 0);

      agents.complete(const [
        Agent(id: 'agent-ceo', name: 'Chief Example', role: 'ceo'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Chief Example'), findsOneWidget);
      expect(createEnabled(tester), isTrue);
    });

    testWidgets('an agent failure allows an explicit Unassigned (AC3)', (
      tester,
    ) async {
      final agents = FakeAgentRepository()..failWith = const Offline();
      final h = await pumpNewIssue(tester, agents: agents);

      expect(find.text("Couldn't load agents"), findsOneWidget);
      await tester.enterText(titleField(), 'No assignee');
      await tester.pump();
      expect(createEnabled(tester), isFalse);

      await tester.tap(find.bySemanticsLabel('Assignee: Unassigned'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unassigned').last);
      await tester.pumpAndSettle();
      expect(createEnabled(tester), isTrue);

      await tester.tap(find.text('Create issue'));
      await tester.pumpAndSettle();
      expect(h.issues.lastCreateAssigneeId, isNull);
      expect(h.issues.created, hasLength(1));
    });

    testWidgets('a project load failure keeps the form usable (AC3)', (
      tester,
    ) async {
      final projects = FakeProjectRepository()..failWith = const Offline();
      final h = await pumpNewIssue(tester, projects: projects);
      expect(projects.calls, 0);

      await tester.tap(find.bySemanticsLabel('Project: None'));
      await tester.pumpAndSettle();
      expect(projects.calls, 1);
      expect(find.text("Couldn't load projects. Try again."), findsOneWidget);

      dismissAppToast();
      await tester.pump();
      await tester.enterText(titleField(), 'A title');
      await tester.pump();
      await tester.tap(find.text('Create issue'));
      await tester.pumpAndSettle();

      expect(h.issues.lastCreateProjectId, isNull);
      expect(h.issues.created, hasLength(1));
    });

    testWidgets('sends the picked assignee and project', (tester) async {
      final projects = FakeProjectRepository();
      final h = await pumpNewIssue(tester, projects: projects);
      expect(projects.calls, 0);

      await tester.tap(find.bySemanticsLabel('Project: None'));
      await tester.pumpAndSettle();
      expect(projects.calls, 1);
      await tester.tap(find.text('Website'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Assignee: Chief Example'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Engineer Example').last);
      await tester.pumpAndSettle();

      await tester.enterText(titleField(), 'Ship the new form');
      await tester.pump();
      await tester.tap(find.text('Create issue'));
      await tester.pumpAndSettle();

      expect(h.issues.lastCreateTitle, 'Ship the new form');
      expect(h.issues.lastCreateDescription, isNull);
      expect(h.issues.lastCreateAssigneeId, 'agent-eng');
      expect(h.issues.lastCreateProjectId, 'project-web');
      expect(h.issues.created.single.status, IssueStatus.todo);
    });
  });

  group('S7 create (AC4-AC5, G2, G5, G6)', () {
    testWidgets('success lands on S6 and refreshes the Inbox (AC4)', (
      tester,
    ) async {
      final h = await pumpNewIssue(tester);
      final feedCalls = h.inbox.feedCalls;

      await tester.enterText(titleField(), 'Ship the new form');
      await tester.pump();
      await tester.tap(find.text('Create issue'));
      await tester.pumpAndSettle();

      expect(h.issues.createCalls, 1);
      expect(h.issues.created.single.title, 'Ship the new form');
      expect(find.text('ACM-101'), findsOneWidget);
      expect(find.text('Ship the new form'), findsOneWidget);
      expect(h.inbox.feedCalls, greaterThan(feedCalls));

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Description'), findsNothing);
    });

    testWidgets('a 5xx keeps every field and shows the error (G5)', (
      tester,
    ) async {
      final h = await pumpNewIssue(tester);
      h.issues.failNextCreate = const Server(500);

      await tester.enterText(titleField(), 'Fix the thing');
      await tester.enterText(descriptionField(), 'Keep this text');
      await tester.pump();
      await tester.tap(find.text('Create issue'));
      await tester.pumpAndSettle();

      expect(h.issues.createCalls, 1);
      expect(titleText(tester), 'Fix the thing');
      expect(descriptionText(tester), 'Keep this text');
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(createEnabled(tester), isTrue);
    });

    testWidgets('offline keeps every field (G2)', (tester) async {
      final h = await pumpNewIssue(tester);
      h.issues.failNextCreate = const Offline();

      await tester.enterText(titleField(), 'Fix the thing');
      await tester.enterText(descriptionField(), 'Keep this text');
      await tester.pump();
      await tester.tap(find.text('Create issue'));
      await tester.pumpAndSettle();

      expect(find.text("Can't reach x.example.test"), findsOneWidget);
      expect(titleText(tester), 'Fix the thing');
      expect(descriptionText(tester), 'Keep this text');
    });

    testWidgets('a double tap creates one issue (G6)', (tester) async {
      final h = await pumpNewIssue(tester);
      h.issues.latency = const Duration(milliseconds: 200);

      await tester.enterText(titleField(), 'Only once');
      await tester.pump();
      await tester.tap(find.text('Create issue'));
      await tester.tap(find.text('Create issue'));
      await tester.pumpAndSettle();

      expect(h.issues.createCalls, 1);
      expect(h.issues.created, hasLength(1));
    });

    testWidgets('an answer without an id falls back to S2 with Created', (
      tester,
    ) async {
      final h = await pumpNewIssue(tester);
      h.issues.createWithoutId = true;

      await tester.enterText(titleField(), 'Created anyway');
      await tester.pump();
      await tester.tap(find.text('Create issue'));
      await tester.pumpAndSettle();

      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Created'), findsOneWidget);
      dismissAppToast();
      await tester.pump();
    });
  });

  group('S7 leaving and accessibility (AC6, G8)', () {
    testWidgets('unsaved text asks before leaving (AC6)', (tester) async {
      await pumpNewIssue(tester);
      await tester.enterText(titleField(), 'A draft');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this draft?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(titleText(tester), 'A draft');

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Description'), findsNothing);
    });

    testWidgets('an empty form closes without a prompt (AC6)', (tester) async {
      await pumpNewIssue(tester);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Discard this draft?'), findsNothing);
      expect(find.text('Inbox'), findsOneWidget);
    });

    testWidgets('XXL text keeps the create action reachable (G8)', (
      tester,
    ) async {
      await pumpNewIssue(tester, textScale: 2);

      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Create issue'), findsOneWidget);
      final rect = tester.getRect(find.text('Create issue'));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(rect.bottom, lessThanOrEqualTo(screen.height));
    });
  });
}
