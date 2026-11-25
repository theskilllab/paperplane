import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/interaction.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/ui/ui.dart';

import '../inbox/inbox_harness.dart' show TrackingInbox, pumpInbox, testNow;

Interaction interaction({
  required InteractionKind kind,
  required Map<String, Object?> payload,
  String id = 'int-01',
  String issueId = 'ACM-12',
  String title = 'Question',
  InteractionStatus status = InteractionStatus.pending,
  Map<String, Object?> result = const {},
  String? acceptanceBlocker,
}) => Interaction(
  id: id,
  issueId: issueId,
  companyId: 'company-demo-1',
  rawKind: kind.wire,
  kind: kind,
  status: status,
  title: title,
  summary: 'Summary',
  payload: payload,
  result: result,
  acceptanceBlocker: acceptanceBlocker,
);

Map<String, Object?> confirmationPayload({
  bool requiresReason = true,
  Map<String, Object?>? extra,
}) => {
  'version': 1,
  'prompt': 'Approve the example change?',
  'acceptLabel': 'Approve',
  'rejectLabel': 'Request changes',
  'rejectRequiresReason': requiresReason,
  'rejectReasonLabel': 'What should change?',
  'allowDeclineReason': true,
  ...?extra,
};

Map<String, Object?> checklistPayload() => {
  'version': 1,
  'prompt': 'Which milestones do you approve?',
  'options': [
    {'id': 'milestone-a', 'label': 'Milestone A'},
    {'id': 'milestone-b', 'label': 'Milestone B'},
  ],
  'minSelected': 1,
  'maxSelected': 2,
  'defaultSelectedOptionIds': ['milestone-a'],
  'acceptLabel': 'Approve selected',
  'rejectLabel': 'Request changes',
  'rejectRequiresReason': false,
  'allowDeclineReason': true,
};

Map<String, Object?> questionsPayload() => {
  'version': 1,
  'questions': [
    {
      'id': 'channel',
      'prompt': 'Which channel should the next build go to?',
      'required': true,
      'selectionMode': 'single',
      'allowOther': false,
      'options': [
        {'id': 'stable', 'label': 'Stable'},
        {'id': 'beta', 'label': 'Beta'},
      ],
    },
    {
      'id': 'notes',
      'prompt': 'Anything the agent should know?',
      'required': false,
      'selectionMode': 'single',
      'allowOther': true,
      'options': [
        {
          'id': 'paperclip_text_answer',
          'label': 'Type an answer',
          'freeText': true,
        },
      ],
    },
  ],
  'questionSet': {
    'schema': 'paperclip.question_set.v1',
    'questions': [
      {
        'id': 'channel',
        'prompt': 'Which channel should the next build go to?',
        'required': true,
        'answerMode': 'single_select',
        'options': [
          {'id': 'stable', 'label': 'Stable'},
          {'id': 'beta', 'label': 'Beta'},
        ],
      },
      {
        'id': 'notes',
        'prompt': 'Anything the agent should know?',
        'required': false,
        'answerMode': 'text',
      },
    ],
  },
};

FakeInteractionRepository questionsRepo() => FakeInteractionRepository(
  now: () => testNow,
  interactions: [
    interaction(
      kind: InteractionKind.askUserQuestions,
      title: 'Release channel question',
      payload: questionsPayload(),
    ),
  ],
);

Map<String, Object?> limitedTextPayload() => {
  'version': 1,
  'questions': [
    {
      'id': 'note',
      'prompt': 'Add a short note',
      'required': true,
      'selectionMode': 'single',
      'allowOther': false,
      'options': [
        {
          'id': 'paperclip_text_answer',
          'label': 'Type an answer',
          'freeText': true,
        },
      ],
    },
  ],
  'questionSet': {
    'schema': 'paperclip.question_set.v1',
    'questions': [
      {
        'id': 'note',
        'prompt': 'Add a short note',
        'required': true,
        'answerMode': 'text',
        'textValidation': {'minLength': 3, 'maxLength': 5},
      },
    ],
  },
};

Map<String, Object?> suggestedPayload() => {
  'version': 1,
  'tasks': [
    {'clientKey': 'task-a', 'title': 'First task', 'priority': 'medium'},
    {'clientKey': 'task-b', 'title': 'Second task', 'priority': 'low'},
  ],
};

Future<void> openQuestionSheet(WidgetTester tester) async {
  final row = find.text('Which release channel should we use?');
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(row);
  await tester.pumpAndSettle();
}

AppButton button(WidgetTester tester, String label) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, label));

void main() {
  testWidgets('questions: submit waits for a required choice, then answers', (
    tester,
  ) async {
    final interactions = questionsRepo();
    final inbox = TrackingInbox()
      ..onFetch = (companyId) async {
        final feed = AttentionFeed.fromJson(
          demoAttentionJsonFor(companyId, testNow),
        );
        final items = feed.items
            .where(
              (item) => !(interactions.respondCalls > 0 && item.id == 'att-03'),
            )
            .toList();
        return AttentionFeed(
          items: items,
          totalCount: items.length,
          countsBySourceKind: feed.countsBySourceKind,
        );
      };
    final h = await pumpInbox(tester, inbox: inbox, interactions: interactions);
    await openQuestionSheet(tester);

    expect(button(tester, 'Send answer').onPressed, isNull);

    await tester.tap(find.text('Stable'));
    await tester.pump();
    expect(button(tester, 'Send answer').onPressed, isNotNull);
    expect(
      tester.getSize(find.widgetWithText(AppButton, 'Send answer')).height,
      greaterThanOrEqualTo(48),
    );

    await tester.enterText(find.byType(TextField).last, 'Ship it.');
    await tester.tap(find.widgetWithText(AppButton, 'Send answer'));
    await tester.pumpAndSettle();

    expect(h.interactions.respondCalls, 1);
    expect(h.interactions.lastAnswers, hasLength(2));
    expect(h.interactions.lastAnswers!.first.questionId, 'channel');
    expect(h.interactions.lastAnswers!.first.optionIds, ['stable']);
    expect(h.interactions.lastAnswers!.last.otherText, 'Ship it.');
    expect(find.text('Answer sent'), findsOneWidget);
    expect(find.text('Which release channel should we use?'), findsNothing);
    dismissAppToast();
  });

  testWidgets('confirmation: reject needs a reason when the server asks', (
    tester,
  ) async {
    final h = await pumpInbox(
      tester,
      interactions: FakeInteractionRepository(
        now: () => testNow,
        interactions: [
          interaction(
            kind: InteractionKind.requestConfirmation,
            title: 'Approve the example change?',
            payload: confirmationPayload(),
          ),
        ],
      ),
    );
    await openQuestionSheet(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Request changes'));
    await tester.pumpAndSettle();
    expect(button(tester, 'Request changes').onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Please add a test.');
    await tester.pump();
    expect(button(tester, 'Request changes').onPressed, isNotNull);

    await tester.tap(find.widgetWithText(AppButton, 'Request changes'));
    await tester.pumpAndSettle();

    expect(h.interactions.rejectCalls, 1);
    expect(h.interactions.lastReason, 'Please add a test.');
    expect(find.text('Rejected'), findsOneWidget);
    dismissAppToast();
  });

  testWidgets('confirmation: approve is one tap', (tester) async {
    final h = await pumpInbox(
      tester,
      interactions: FakeInteractionRepository(
        now: () => testNow,
        interactions: [
          interaction(
            kind: InteractionKind.requestConfirmation,
            title: 'Approve the example change?',
            payload: confirmationPayload(requiresReason: false),
          ),
        ],
      ),
    );
    await openQuestionSheet(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(h.interactions.acceptCalls, 1);
    expect(find.text('Confirmed'), findsOneWidget);
    dismissAppToast();
  });

  testWidgets('checklist: selections respect the server bounds', (
    tester,
  ) async {
    final h = await pumpInbox(
      tester,
      interactions: FakeInteractionRepository(
        now: () => testNow,
        interactions: [
          interaction(
            kind: InteractionKind.requestCheckboxConfirmation,
            title: 'Approve the example milestones',
            payload: checklistPayload(),
          ),
        ],
      ),
    );
    await openQuestionSheet(tester);

    expect(button(tester, 'Approve selected').onPressed, isNotNull);
    await tester.tap(find.text('Milestone B'));
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, 'Approve selected'));
    await tester.pumpAndSettle();

    expect(h.interactions.acceptCalls, 1);
    expect(
      h.interactions.lastOptionIds,
      containsAll(['milestone-a', 'milestone-b']),
    );
    dismissAppToast();
  });

  testWidgets('suggested tasks: accept sends every client key', (tester) async {
    final h = await pumpInbox(
      tester,
      interactions: FakeInteractionRepository(
        now: () => testNow,
        interactions: [
          interaction(
            kind: InteractionKind.suggestTasks,
            title: 'Suggested follow-up tasks',
            payload: suggestedPayload(),
          ),
        ],
      ),
    );
    await openQuestionSheet(tester);

    expect(find.text('First task'), findsOneWidget);
    expect(find.text('Second task'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Create tasks'));
    await tester.pumpAndSettle();

    expect(h.interactions.acceptCalls, 1);
    expect(h.interactions.lastClientKeys, ['task-a', 'task-b']);
    expect(find.text('Tasks created'), findsOneWidget);
    dismissAppToast();
  });

  testWidgets('a toolAction confirmation has no inline button', (tester) async {
    final h = await pumpInbox(
      tester,
      interactions: FakeInteractionRepository(
        now: () => testNow,
        interactions: [
          interaction(
            kind: InteractionKind.requestConfirmation,
            title: 'Run the example deploy tool',
            payload: confirmationPayload(
              extra: {
                'toolAction': {
                  'version': 1,
                  'actionRequestId': 'a',
                  'toolName': 'deploy',
                  'toolDisplayName': 'Deploy',
                  'risk': 'destructive',
                  'previewMarkdown': 'Deploy to staging.',
                  'argumentsSummaryJson': '{}',
                  'argumentsHash': 'sha256:x',
                  'expiresAt': '2026-11-07T11:00:00.000Z',
                },
              },
            ),
          ),
        ],
      ),
    );
    await openQuestionSheet(tester);

    expect(
      find.text(
        "This question type isn't supported in the app yet. Open it in "
        'Paperclip to answer.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(AppButton, 'Approve'), findsNothing);
    await tester.tap(find.widgetWithText(AppButton, 'Open in Paperclip'));
    await tester.pumpAndSettle();

    expect(h.opened, hasLength(1));
    expect(
      h.opened.single.toString(),
      'https://x.example.test/ACM/issues/ACM-12#interaction-int-01',
    );
  });

  testWidgets('a connection-authorization confirmation has no inline button', (
    tester,
  ) async {
    final h = await pumpInbox(
      tester,
      interactions: FakeInteractionRepository(
        now: () => testNow,
        interactions: [
          interaction(
            kind: InteractionKind.requestConfirmation,
            title: 'Authorize the example connection',
            payload: confirmationPayload(
              extra: {
                'connectionAuthorization': {
                  'version': 1,
                  'authorizationId': 'a',
                  'serviceName': 'Example Service',
                  'serviceSlug': 'example-service',
                  'scopes': ['example.read'],
                  'expiresAt': '2026-11-07T11:00:00.000Z',
                },
              },
            ),
          ),
        ],
      ),
    );
    await openQuestionSheet(tester);

    expect(
      find.text(
        "This question type isn't supported in the app yet. Open it in "
        'Paperclip to answer.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(AppButton, 'Approve'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Authorize'), findsNothing);
    await tester.tap(find.widgetWithText(AppButton, 'Open in Paperclip'));
    await tester.pumpAndSettle();

    expect(h.opened, hasLength(1));
    expect(
      h.opened.single.toString(),
      'https://x.example.test/ACM/issues/ACM-12#interaction-int-01',
    );
  });

  testWidgets('a qualityReview confirmation has no inline button', (
    tester,
  ) async {
    final h = await pumpInbox(
      tester,
      interactions: FakeInteractionRepository(
        now: () => testNow,
        interactions: [
          interaction(
            kind: InteractionKind.requestConfirmation,
            title: 'Sign off the example quality review',
            payload: confirmationPayload(
              requiresReason: false,
              extra: {
                'qualityReview': {
                  'stageKey': 'example-review',
                  'requirementHash': 'sha256:x',
                },
              },
            ),
          ),
        ],
      ),
    );
    await openQuestionSheet(tester);

    expect(
      find.text(
        "This question type isn't supported in the app yet. Open it in "
        'Paperclip to answer.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(AppButton, 'Approve'), findsNothing);
    await tester.tap(find.widgetWithText(AppButton, 'Open in Paperclip'));
    await tester.pumpAndSettle();

    expect(h.opened, hasLength(1));
  });

  testWidgets('an unknown confirmation key has no inline button', (
    tester,
  ) async {
    await pumpInbox(
      tester,
      interactions: FakeInteractionRepository(
        now: () => testNow,
        interactions: [
          interaction(
            kind: InteractionKind.requestConfirmation,
            title: 'Approve the future governed action',
            payload: confirmationPayload(
              requiresReason: false,
              extra: {
                'futureGovernedAction': {'actionId': 'example-action'},
              },
            ),
          ),
        ],
      ),
    );
    await openQuestionSheet(tester);

    expect(
      find.text(
        "This question type isn't supported in the app yet. Open it in "
        'Paperclip to answer.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(AppButton, 'Approve'), findsNothing);
  });

  testWidgets('an acceptanceBlocker disables inline accept', (tester) async {
    final h = await pumpInbox(
      tester,
      interactions: FakeInteractionRepository(
        now: () => testNow,
        interactions: [
          interaction(
            kind: InteractionKind.requestConfirmation,
            title: 'Approve the example change?',
            payload: confirmationPayload(requiresReason: false),
            acceptanceBlocker: 'workspace_sync_pending',
          ),
        ],
      ),
    );
    await openQuestionSheet(tester);

    expect(button(tester, 'Approve').onPressed, isNull);
    expect(find.textContaining('Preparing approval'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Request changes'), findsOneWidget);
    expect(h.interactions.acceptCalls, 0);
  });

  testWidgets('403 is read-only with the server message', (tester) async {
    final fake = FakeInteractionRepository(
      now: () => testNow,
      interactions: [
        interaction(
          kind: InteractionKind.requestConfirmation,
          title: 'Approve the example change?',
          payload: confirmationPayload(requiresReason: false),
        ),
      ],
    )..writeError = const Forbidden('Only certain users can answer');
    final h = await pumpInbox(tester, interactions: fake);
    await openQuestionSheet(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Approve'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text("You can't do that"), findsOneWidget);
    expect(find.text('Only certain users can answer'), findsOneWidget);
    expect(h.interactions.acceptCalls, 0);
    expect(find.widgetWithText(AppButton, 'Close'), findsOneWidget);
  });

  testWidgets('409 while the row is still pending shows the server message', (
    tester,
  ) async {
    final fake =
        FakeInteractionRepository(
            now: () => testNow,
            interactions: [
              interaction(
                kind: InteractionKind.requestConfirmation,
                title: 'Approve the example change?',
                payload: confirmationPayload(requiresReason: false),
              ),
            ],
          )
          ..writeError = const AlreadyHandled(
            409,
            message:
                'Cannot accept interaction: the workspace has not finished '
                'syncing',
          );
    final h = await pumpInbox(tester, interactions: fake);
    final before = h.inbox.feedCalls;
    await openQuestionSheet(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Already handled'), findsNothing);
    expect(find.text('Not ready yet'), findsOneWidget);
    expect(find.textContaining('has not finished syncing'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Approve'), findsOneWidget);
    expect(fake.listCalls, greaterThanOrEqualTo(2));
    expect(h.inbox.feedCalls, greaterThan(before));
  });

  testWidgets('409 after the re-read row resolves shows Already handled', (
    tester,
  ) async {
    final fake =
        FakeInteractionRepository(
            now: () => testNow,
            interactions: [
              interaction(
                kind: InteractionKind.requestConfirmation,
                title: 'Approve the example change?',
                payload: confirmationPayload(requiresReason: false),
              ),
            ],
          )
          ..writeError = const AlreadyHandled(409)
          ..resolveOnConflict = true;
    final h = await pumpInbox(tester, interactions: fake);
    final before = h.inbox.feedCalls;
    await openQuestionSheet(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Already handled'), findsOneWidget);
    expect(fake.listCalls, greaterThanOrEqualTo(2));
    expect(h.inbox.feedCalls, greaterThan(before));
  });

  testWidgets('422 keeps the sheet open with the validation message', (
    tester,
  ) async {
    final fake = FakeInteractionRepository(
      now: () => testNow,
      interactions: [
        interaction(
          kind: InteractionKind.suggestTasks,
          title: 'Suggested follow-up tasks',
          payload: suggestedPayload(),
        ),
      ],
    )..writeError = const Server(422, message: 'Select at least one task');
    await pumpInbox(tester, interactions: fake);
    await openQuestionSheet(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Create tasks'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.textContaining('Select at least one task'), findsOneWidget);
    expect(find.text('First task'), findsOneWidget);
  });

  testWidgets('closing with typed text asks before discarding', (tester) async {
    final h = await pumpInbox(tester, interactions: questionsRepo());
    await openQuestionSheet(tester);

    await tester.tap(find.text('Stable'));
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.text('Discard this answer?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Release channel question'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(h.interactions.respondCalls, 0);
    expect(find.text('Release channel question'), findsNothing);
  });

  testWidgets('AC2: free text outside the server lengths cannot send', (
    tester,
  ) async {
    await pumpInbox(
      tester,
      interactions: FakeInteractionRepository(
        now: () => testNow,
        interactions: [
          interaction(
            kind: InteractionKind.askUserQuestions,
            title: 'Short note',
            payload: limitedTextPayload(),
          ),
        ],
      ),
    );
    await openQuestionSheet(tester);

    expect(button(tester, 'Send answer').onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'ab');
    await tester.pump();
    expect(find.text('Use at least 3 characters.'), findsOneWidget);
    expect(button(tester, 'Send answer').onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'abcdef');
    await tester.pump();
    expect(find.text('Up to 5 characters.'), findsOneWidget);
    expect(button(tester, 'Send answer').onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'abcd');
    await tester.pump();
    expect(button(tester, 'Send answer').onPressed, isNotNull);
  });

  testWidgets('G8: choice rows are labelled 48 pt targets under a heading', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpInbox(tester, interactions: questionsRepo());
    await openQuestionSheet(tester);

    expect(find.text('Release channel question'), findsOneWidget);

    final heading = find.bySemanticsLabel('Question');
    expect(heading, findsOneWidget);
    expect(
      tester.getSemantics(heading).getSemanticsData().flagsCollection.isHeader,
      isTrue,
    );

    for (final label in ['Stable', 'Beta']) {
      final row = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      );
      expect(row, findsOneWidget, reason: label);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel(RegExp(label)), findsWidgets);
    }
    handle.dispose();
  });

  testWidgets('offline: the sheet keeps the question with Retry and Close', (
    tester,
  ) async {
    final fake = FakeInteractionRepository(
      now: () => testNow,
      interactions: [
        interaction(
          kind: InteractionKind.requestConfirmation,
          title: 'Approve the example change?',
          payload: confirmationPayload(requiresReason: false),
        ),
      ],
    )..listError = const Offline();
    await pumpInbox(tester, interactions: fake);
    await openQuestionSheet(tester);

    expect(find.text("Can't reach x.example.test"), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Retry'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Close'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Approve'), findsNothing);

    fake.listError = null;
    await tester.tap(find.widgetWithText(AppButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppButton, 'Approve'), findsOneWidget);
  });

  testWidgets('double tap sends one request', (tester) async {
    final fake = questionsRepo()..latency = const Duration(milliseconds: 300);
    final h = await pumpInbox(tester, interactions: fake);
    await openQuestionSheet(tester);

    await tester.tap(find.text('Stable'));
    await tester.pump();
    final send = find.widgetWithText(AppButton, 'Send answer');
    await tester.tap(send);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(send, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(h.interactions.respondCalls, 1);
    dismissAppToast();
  });
}
