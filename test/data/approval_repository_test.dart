import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/approval.dart';
import 'package:paperplane/data/approval_repository.dart';

import '../support/fake_adapter.dart';
import '../support/fixtures.dart';

ApiClient clientFor(FakeAdapter adapter) => ApiClient(
  baseUrl: Uri.parse('https://paperclip.example.test'),
  adapter: adapter,
);

void main() {
  group('HttpApprovalRepository', () {
    test('fetch reads GET /approvals/{id}', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('approval_pending.json')),
      );
      final approval = await HttpApprovalRepository(clientFor(adapter))
          .fetch('approval-1');

      expect(approval.id, 'approval-recorded-1');
      expect(approval.status, ApprovalStatus.pending);
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.path, '/approvals/approval-1');
      expect(adapter.requests.single.headers, isNot(contains('Authorization')));
    });

    test('linkedIssues reads GET /approvals/{id}/issues', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('approval_issues.json')),
      );
      final issues = await HttpApprovalRepository(clientFor(adapter))
          .linkedIssues('approval-1');

      expect(issues, hasLength(1));
      expect(issues.single.identifier, 'REC-12');
      expect(adapter.requests.single.path, '/approvals/approval-1/issues');
    });

    test('approve sends the note and returns the updated approval', () async {
      final decided = loadFixtureMap('approval_decided.json');
      final adapter = FakeAdapter((o) async => jsonBody(decided));
      final approval = await HttpApprovalRepository(clientFor(adapter))
          .approve('approval-1', decisionNote: '  Looks good.  ');

      expect(approval.status, ApprovalStatus.approved);
      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/approvals/approval-1/approve');
      expect(sent.data, {'decisionNote': 'Looks good.'});
    });

    test('reject sends the note to /reject', () async {
      final decided = loadFixtureMap('approval_decided.json')
        ..['status'] = 'rejected';
      final adapter = FakeAdapter((o) async => jsonBody(decided));
      await HttpApprovalRepository(clientFor(adapter))
          .reject('approval-1', decisionNote: 'Not yet');

      final sent = adapter.requests.single;
      expect(sent.path, '/approvals/approval-1/reject');
      expect(sent.data, {'decisionNote': 'Not yet'});
    });

    test('an empty note sends an empty body', () async {
      final decided = loadFixtureMap('approval_decided.json');
      final adapter = FakeAdapter((o) async => jsonBody(decided));
      await HttpApprovalRepository(clientFor(adapter))
          .approve('approval-1', decisionNote: '   ');

      expect(adapter.requests.single.data, <String, Object?>{});
    });

    test('409 and 422 on a decision are AlreadyHandled', () async {
      for (final status in [409, 422]) {
        final adapter = FakeAdapter(
          (o) async =>
              jsonBody(loadFixture('approval_conflict.json'), status: status),
        );
        await expectLater(
          HttpApprovalRepository(clientFor(adapter)).approve('approval-1'),
          throwsA(isA<AlreadyHandled>()),
        );
      }
    });

    test('a decision body without an id re-reads the approval', () async {
      var calls = 0;
      final adapter = FakeAdapter((o) async {
        calls++;
        return calls == 1
            ? jsonBody(const <String, Object?>{})
            : jsonBody(loadFixture('approval_decided.json'));
      });
      final approval = await HttpApprovalRepository(clientFor(adapter))
          .approve('approval-1');

      expect(approval.id, 'approval-recorded-2');
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.path, '/approvals/approval-1');
    });
  });
}
