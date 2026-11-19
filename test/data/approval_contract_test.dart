import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/models/approval.dart';

import '../support/fixtures.dart';

/// Contract test for the approval detail and linked-issue payloads.
///
/// The fixtures follow payloads recorded from a real Paperclip instance and
/// then scrubbed (see the fixture README). Parsing them with the app's models
/// fails here when the server changes a field the app reads.
void main() {
  group('recorded approval detail payload', () {
    final pending = Approval.fromJson(loadFixtureMap('approval_pending.json'));

    test('pending approval parses', () {
      expect(pending.id, 'approval-recorded-1');
      expect(pending.type, 'hire_agent');
      expect(pending.status, ApprovalStatus.pending);
      expect(pending.isPending, isTrue);
      expect(pending.title, 'Hire a recorded example');
      expect(pending.summary, isNull);
      expect(pending.requestedByAgentId, 'agent-recorded-1');
      expect(pending.decidedByUserId, isNull);
      expect(pending.decidedAt, isNull);
      expect(pending.createdAt, DateTime.utc(2026, 11, 6, 9, 30));
    });

    test('the free-form payload keeps its values', () {
      expect(pending.payload['role'], 'engineer');
      expect(pending.payload['budgetMonthlyCents'], 0);
      expect(pending.payload['adapterConfig'], isA<Map<String, Object?>>());
      expect(pending.hasKnownBody, isTrue);
    });

    test('decided approval parses', () {
      final decided = Approval.fromJson(
        loadFixtureMap('approval_decided.json'),
      );
      expect(decided.status, ApprovalStatus.approved);
      expect(decided.isPending, isFalse);
      expect(decided.type, 'request_board_approval');
      expect(decided.decidedByUserId, 'user-recorded-1');
      expect(decided.decidedAt, DateTime.utc(2026, 11, 5, 10));
      expect(decided.decisionNote, 'Looks good.');
      expect(decided.summary, 'The recorded example passed every check.');
      expect(decided.hasKnownBody, isFalse);
      expect(decided.payload['risks'], isA<List<Object?>>());
    });

    test('linked issue parses', () {
      final issues = [
        for (final entry
            in loadFixture('approval_issues.json')! as List<Object?>)
          LinkedIssue.fromJson((entry! as Map).cast<String, Object?>()),
      ];
      expect(issues, hasLength(1));
      expect(issues.single.identifier, 'REC-12');
      expect(issues.single.title, 'A recorded linked issue');
      expect(issues.single.status, 'done');
    });
  });

  group('tolerant parsing', () {
    test('missing fields do not throw', () {
      final approval = Approval.fromJson(const {});
      expect(approval.id, '');
      expect(approval.status, ApprovalStatus.unknown);
      expect(approval.isPending, isFalse);
      expect(approval.title, 'Approval');
      expect(approval.payload, isEmpty);
    });

    test('an unknown status is unknown, not pending', () {
      final approval = Approval.fromJson(const {
        'id': 'a1',
        'type': 'future_type',
        'status': 'waiting_for_the_moon',
      });
      expect(approval.status, ApprovalStatus.unknown);
      expect(approval.isPending, isFalse);
      expect(approval.hasKnownBody, isFalse);
      expect(approval.title, 'Future type');
    });
  });
}
