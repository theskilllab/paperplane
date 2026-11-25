import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/interaction.dart';
import 'package:paperplane/data/interaction_repository.dart';

import '../support/fake_adapter.dart';
import '../support/fixtures.dart';

ApiClient clientFor(FakeAdapter adapter) => ApiClient(
  baseUrl: Uri.parse('https://paperclip.example.test'),
  adapter: adapter,
);

List<Interaction> recordedInteractions() => [
  for (final entry in loadFixture('interactions.json')! as List<Object?>)
    Interaction.fromJson((entry! as Map).cast<String, Object?>()),
];

void main() {
  group('recorded interactions', () {
    final rows = recordedInteractions();
    final byId = {for (final row in rows) row.id: row};

    test('the fixture covers every kind and the unsafe variants', () {
      expect(
        rows.map((row) => row.kind).toSet(),
        containsAll([
          InteractionKind.askUserQuestions,
          InteractionKind.requestConfirmation,
          InteractionKind.requestCheckboxConfirmation,
          InteractionKind.suggestTasks,
          InteractionKind.requestItemVerdicts,
          InteractionKind.connectionIntent,
          InteractionKind.unknown,
        ]),
      );
    });

    test('the four inline kinds are supported', () {
      for (final id in [
        'int-recorded-questions',
        'int-recorded-confirmation',
        'int-recorded-checklist',
        'int-recorded-suggested-tasks',
      ]) {
        final row = byId[id]!;
        expect(row.isPending, isTrue, reason: id);
        expect(row.canResolveInline, isTrue, reason: id);
        expect(row.support, InteractionSupport.inline, reason: id);
      }
    });

    test('a recorded toolAction confirmation opens in Paperclip', () {
      final row = byId['int-recorded-tool-action']!;
      expect(row.kind, InteractionKind.requestConfirmation);
      expect(row.confirmation.hasToolAction, isTrue);
      expect(row.canResolveInline, isFalse);
    });

    test(
      'a recorded connection-authorization confirmation opens in Paperclip',
      () {
        final row = byId['int-recorded-connection-authorization']!;
        expect(row.kind, InteractionKind.requestConfirmation);
        expect(row.confirmation.hasConnectionAuthorization, isTrue);
        expect(row.confirmation.isPlain, isFalse);
        expect(row.canResolveInline, isFalse);
      },
    );

    test(
      'secret proposals, verdicts and connection intents open in Paperclip',
      () {
        for (final id in [
          'int-recorded-secret-proposal',
          'int-recorded-verdicts',
          'int-recorded-connection',
        ]) {
          expect(byId[id]!.canResolveInline, isFalse, reason: id);
        }
      },
    );

    test('questions with a number mode open in Paperclip', () {
      final row = byId['int-recorded-number-question']!;
      expect(row.questionForm.isSupported, isFalse);
      expect(row.canResolveInline, isFalse);
    });

    test('a stale document target opens in Paperclip', () {
      final row = byId['int-recorded-stale']!;
      expect(row.confirmation.isStaleTarget, isTrue);
      expect(row.canResolveInline, isFalse);
    });

    test('an unknown kind keeps its raw value and opens in Paperclip', () {
      final row = byId['int-recorded-unknown']!;
      expect(row.kind, InteractionKind.unknown);
      expect(row.rawKind, 'example_future_kind');
      expect(row.canResolveInline, isFalse);
    });

    test('question fields parse', () {
      final form = byId['int-recorded-questions']!.questionForm;
      expect(form.questions, hasLength(2));
      expect(form.questions.first.id, 'channel');
      expect(form.questions.first.multiSelect, isFalse);
      expect(form.questions.first.options.map((o) => o.label), [
        'Stable',
        'Beta',
      ]);
      expect(form.questions.last.isFreeTextOnly, isTrue);
    });

    test('checklist defaults and bounds parse', () {
      final checklist = byId['int-recorded-checklist']!.checklist;
      expect(checklist.options, hasLength(2));
      expect(checklist.defaultSelected, {'milestone-a'});
      expect(checklist.minSelected, 1);
      expect(checklist.maxSelected, 2);
      expect(checklist.isValid({'milestone-a'}), isTrue);
      expect(checklist.isValid({}), isFalse);
    });

    test('suggested task keys parse', () {
      final tasks = byId['int-recorded-suggested-tasks']!.suggestedTasks;
      expect(tasks.tasks.map((task) => task.clientKey), ['task-a', 'task-b']);
    });
  });

  group('HttpInteractionRepository', () {
    test('list uses the issue endpoint', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('interactions.json')),
      );
      final rows = await HttpInteractionRepository(clientFor(adapter))
          .list('issue-1');

      expect(rows, hasLength(12));
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.path, '/issues/issue-1/interactions');
    });

    test('find re-reads the list, there is no get-by-id call', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('interactions.json')),
      );
      final repo = HttpInteractionRepository(clientFor(adapter));

      final found = await repo.find('issue-1', 'int-recorded-confirmation');
      final missing = await repo.find('issue-1', 'missing');

      expect(found?.id, 'int-recorded-confirmation');
      expect(missing, isNull);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.every(
          (request) =>
              request.path == '/issues/issue-1/interactions' &&
              request.method == 'GET',
        ),
        isTrue,
      );
    });

    test('respond posts the answers in the server shape', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody({
          'id': 'int-recorded-questions',
          'issueId': 'issue-1',
          'kind': 'ask_user_questions',
          'status': 'answered',
          'payload': const <String, Object?>{},
          'result': const <String, Object?>{},
        }),
      );
      final repo = HttpInteractionRepository(clientFor(adapter));

      final result = await repo.respond('issue-1', 'int-1', const [
        QuestionAnswer(questionId: 'channel', optionIds: ['stable']),
        QuestionAnswer(
          questionId: 'notes',
          optionIds: ['paperclip_text_answer'],
          otherText: 'Ship it.',
        ),
      ]);

      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/issues/issue-1/interactions/int-1/respond');
      expect(sent.data, {
        'answers': [
          {
            'questionId': 'channel',
            'optionIds': ['stable'],
          },
          {
            'questionId': 'notes',
            'optionIds': ['paperclip_text_answer'],
            'otherText': 'Ship it.',
          },
        ],
      });
      expect(result.status, InteractionStatus.answered);
    });

    test(
      'accept sends client keys and option ids; reject sends a reason',
      () async {
        final adapter = FakeAdapter(
          (o) async => jsonBody({
            'id': 'int-1',
            'issueId': 'issue-1',
            'kind': 'request_checkbox_confirmation',
            'status': 'accepted',
            'payload': const <String, Object?>{},
            'result': const <String, Object?>{},
          }),
        );
        final repo = HttpInteractionRepository(clientFor(adapter));

        await repo.accept(
          'issue-1',
          'int-1',
          selectedClientKeys: const ['task-a'],
          selectedOptionIds: const ['milestone-a'],
        );
        await repo.reject('issue-1', 'int-1', reason: 'Not yet.');

        expect(
          adapter.requests[0].path,
          '/issues/issue-1/interactions/int-1/accept',
        );
        expect(adapter.requests[0].data, {
          'selectedClientKeys': ['task-a'],
          'selectedOptionIds': ['milestone-a'],
        });
        expect(
          adapter.requests[1].path,
          '/issues/issue-1/interactions/int-1/reject',
        );
        expect(adapter.requests[1].data, {'reason': 'Not yet.'});
      },
    );

    test('409 means already handled, even on an interaction', () async {
      final errors = loadFixtureMap('interaction_errors.json');
      final adapter = FakeAdapter(
        (o) async => jsonBody(errors['409'], status: 409),
      );
      final repo = HttpInteractionRepository(clientFor(adapter));

      await expectLater(
        repo.accept('issue-1', 'int-1'),
        throwsA(isA<AlreadyHandled>()),
      );
    });

    test('422 stays a validation error with the server text', () async {
      final errors = loadFixtureMap('interaction_errors.json');
      final adapter = FakeAdapter(
        (o) async => jsonBody(errors['422'], status: 422),
      );
      final repo = HttpInteractionRepository(clientFor(adapter));

      await expectLater(
        repo.accept('issue-1', 'int-1'),
        throwsA(
          isA<Server>()
              .having((e) => e.status, 'status', 422)
              .having(
                (e) => e.message,
                'message',
                'Select at least one suggested task',
              ),
        ),
      );
    });

    test('400 stays a validation error with the server text', () async {
      final errors = loadFixtureMap('interaction_errors.json');
      final adapter = FakeAdapter(
        (o) async => jsonBody(errors['400'], status: 400),
      );
      final repo = HttpInteractionRepository(clientFor(adapter));

      await expectLater(
        repo.respond('issue-1', 'int-1', const []),
        throwsA(
          isA<Server>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.message, 'message', 'Validation error'),
        ),
      );
    });
  });
}
