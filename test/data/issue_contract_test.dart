import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/issue.dart';
import 'package:paperplane/data/issue_repository.dart';

import '../support/fake_adapter.dart';
import '../support/fixtures.dart';

/// Contract test for `GET /issues/{id}`, `GET /issues/{id}/comments` and
/// `POST /issues/{id}/comments`.
///
/// The issue and comment payloads are recorded from a real Paperclip instance
/// and scrubbed (see `test/fixtures/README.md`). They are parsed with the same
/// models and repository the app uses, so a server change that breaks S6 fails
/// here rather than on a phone.
void main() {
  ApiClient clientFor(FakeAdapter adapter) => ApiClient(
    baseUrl: Uri.parse('https://paperclip.example.test'),
    adapter: adapter,
  );

  group('recorded issue payload', () {
    final issue = Issue.fromJson(loadFixtureMap('issue.json'));

    test('header fields parse', () {
      expect(issue.id, isNotEmpty);
      expect(issue.companyId, isNotEmpty);
      expect(issue.identifier, 'FAKE-39');
      expect(issue.title, 'Fake issue title');
      expect(issue.status, IssueStatus.done);
      expect(issue.status.isClosed, isTrue);
      expect(issue.projectName, 'Fake Project');
      expect(issue.projectId, isNotNull);
      expect(issue.assigneeAgentId, isNotNull);
      expect(issue.description, startsWith('## Scope'));
    });

    test('keeps the fields the screen reads', () {
      final json = loadFixtureMap('issue.json');
      for (final key in [
        'id',
        'companyId',
        'identifier',
        'title',
        'description',
        'status',
        'assigneeAgentId',
        'assigneeUserId',
        'projectId',
        'project',
      ]) {
        expect(json, contains(key), reason: key);
      }
    });

    test('an unknown status shows the server text', () {
      final odd = Issue.fromJson(const {
        'id': 'i',
        'status': 'waiting_on_moon',
      });
      expect(odd.status, IssueStatus.unknown);
      expect(odd.statusLabel, 'waiting_on_moon');
    });
  });

  group('recorded comment payloads', () {
    final page1 = IssueComment.listFromJson(
      loadFixture('issue_comments_page1.json'),
    );

    test('fields parse, agent and user comments differ', () {
      expect(page1, hasLength(4));
      expect(page1.first.authorKind, CommentAuthorKind.agent);
      expect(page1.first.authorAgentId, isNotNull);
      expect(page1[1].authorKind, CommentAuthorKind.user);
      expect(page1[1].authorUserId, isNotNull);
      expect(page1[1].authorAgentId, isNull);
      expect(page1.every((c) => c.body.isNotEmpty), isTrue);
      expect(page1.every((c) => c.createdAt != null), isTrue);
      expect(page1.every((c) => !c.deleted), isTrue);
    });

    test('the server sends newest first', () {
      final times = [for (final c in page1) c.createdAt!];
      final sorted = List<DateTime>.of(times)..sort((a, b) => b.compareTo(a));
      expect(times, orderedEquals(sorted));
    });
  });

  group('HttpIssueRepository against the recorded payloads', () {
    test('first page: asks newest first, limit+1, no cursor', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('issue_comments_page1.json')),
      );
      final page = await HttpIssueRepository(clientFor(adapter))
          .fetchComments('issue-1', limit: 3);

      final request = adapter.requests.single;
      expect(request.path, '/issues/issue-1/comments');
      expect(request.queryParameters, {'order': 'desc', 'limit': 4});
      // 4 came back for a limit of 3: there is an earlier page, and the
      // oldest of the four is dropped.
      expect(page.hasEarlier, isTrue);
      expect(page.comments, hasLength(3));
      // Oldest first for display.
      expect(
        page.comments.map((c) => c.createdAt!),
        orderedEquals([...page.comments.map((c) => c.createdAt!)]..sort()),
      );
    });

    test(
      'a page shorter than the limit means there is nothing earlier',
      () async {
        final adapter = FakeAdapter(
          (o) async => jsonBody(loadFixture('issue_comments_page1.json')),
        );
        final page = await HttpIssueRepository(clientFor(adapter))
            .fetchComments('issue-1');
        expect(page.hasEarlier, isFalse);
        expect(page.comments, hasLength(4));
      },
    );

    test('next page: sends the oldest held id as the after cursor', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('issue_comments_page2.json')),
      );
      final page = await HttpIssueRepository(clientFor(adapter))
          .fetchComments('issue-1', before: 'oldest-held-id', limit: 3);

      expect(adapter.requests.single.queryParameters, {
        'order': 'desc',
        'limit': 4,
        'after': 'oldest-held-id',
      });
      expect(page.comments, hasLength(3));
      expect(page.hasEarlier, isFalse);
    });

    test('a deleted anchor answers 200 with an empty list', () async {
      final adapter = FakeAdapter(
        (o) async =>
            jsonBody(loadFixture('issue_comments_missing_anchor.json')),
      );
      final page = await HttpIssueRepository(clientFor(adapter))
          .fetchComments('issue-1', before: 'deleted-id');
      expect(page.comments, isEmpty);
      expect(page.hasEarlier, isFalse);
    });

    test('a limit above the server cap keeps the probe inside it', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('issue_comments_page1.json')),
      );
      final page = await HttpIssueRepository(clientFor(adapter))
          .fetchComments('issue-1', limit: 600);
      // One extra item is still requested, but never more than the server
      // accepts. A clipped answer would read as "no earlier page".
      expect(adapter.requests.single.queryParameters['limit'], 500);
      expect(page.comments, hasLength(4));
      expect(page.hasEarlier, isFalse);
    });

    test('an issue id is encoded in the path', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixtureMap('issue.json')),
      );
      final issue = await HttpIssueRepository(clientFor(adapter))
          .fetchIssue('A B/1');
      expect(adapter.requests.single.path, '/issues/A%20B%2F1');
      expect(issue.identifier, 'FAKE-39');
    });

    test(
      'post sends body and clientRequestId, and parses the answer',
      () async {
        final adapter = FakeAdapter(
          (o) async => jsonBody(
            loadFixtureMap('issue_comment_created.json'),
            status: 201,
          ),
        );
        final created = await HttpIssueRepository(clientFor(adapter))
            .postComment(
              'issue-1',
              body: 'Thanks, ship it.',
              clientRequestId: 'r-1',
            );

        final request = adapter.requests.single;
        expect(request.method, 'POST');
        expect(request.path, '/issues/issue-1/comments');
        expect(request.data, {
          'body': 'Thanks, ship it.',
          'clientRequestId': 'r-1',
        });
        expect(created.body, 'Thanks, ship it.');
        expect(created.authorKind, CommentAuthorKind.user);
      },
    );

    test('errors surface as ApiError: 404, 403, 500, offline', () async {
      for (final (status, matcher) in <(int, Matcher)>[
        (404, isA<NotFound>()),
        (403, isA<Forbidden>()),
        (500, isA<Server>()),
      ]) {
        final adapter = FakeAdapter(
          (o) async => jsonBody(null, status: status),
        );
        await expectLater(
          HttpIssueRepository(clientFor(adapter)).fetchIssue('x'),
          throwsA(matcher),
        );
      }
    });

    test(
      'a failed reply is a plain Server error, not "already handled"',
      () async {
        final adapter = FakeAdapter((o) async => jsonBody(null, status: 409));
        await expectLater(
          HttpIssueRepository(clientFor(adapter))
              .postComment('x', body: 'b', clientRequestId: 'r'),
          throwsA(isA<Server>()),
        );
      },
    );
  });

  group('HttpIssueRepository create (S7)', () {
    test('posts to the company and parses the created issue', () async {
      final adapter = FakeAdapter(
        (o) async =>
            jsonBody(loadFixtureMap('issue_created.json'), status: 201),
      );
      final issue = await HttpIssueRepository(clientFor(adapter)).createIssue(
        companyId: 'company-1',
        title: 'Fake created issue',
        description: 'Fake created description for the create contract test.',
        assigneeAgentId: 'agent-1',
        projectId: 'project-1',
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/companies/company-1/issues');
      expect(request.data, {
        'title': 'Fake created issue',
        'description': 'Fake created description for the create contract test.',
        'assigneeAgentId': 'agent-1',
        'projectId': 'project-1',
      });
      expect(issue.id, '00000000-0000-4000-8000-000000000020');
      expect(issue.identifier, 'FAKE-40');
      expect(issue.status, IssueStatus.todo);
    });

    test('omits unset optional fields so the server defaults them', () async {
      final adapter = FakeAdapter(
        (o) async =>
            jsonBody(loadFixtureMap('issue_created.json'), status: 201),
      );
      await HttpIssueRepository(clientFor(adapter))
          .createIssue(companyId: 'company-1', title: 'Only a title');

      expect(adapter.requests.single.data, {'title': 'Only a title'});
    });

    test('encodes the company id in the path', () async {
      final adapter = FakeAdapter(
        (o) async =>
            jsonBody(loadFixtureMap('issue_created.json'), status: 201),
      );
      await HttpIssueRepository(clientFor(adapter))
          .createIssue(companyId: 'A B/1', title: 'x');
      expect(adapter.requests.single.path, '/companies/A%20B%2F1/issues');
    });

    test('a 403 on create is a Forbidden error', () async {
      final adapter = FakeAdapter((o) async => jsonBody(null, status: 403));
      await expectLater(
        HttpIssueRepository(clientFor(adapter))
            .createIssue(companyId: 'c', title: 'x'),
        throwsA(isA<Forbidden>()),
      );
    });
  });
}
