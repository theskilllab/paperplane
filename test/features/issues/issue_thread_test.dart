import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/issue.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/data/issue_repository.dart';
import 'package:paperplane/features/issues/issue_thread.dart';

/// Repository whose thread a test edits between calls.
class ScriptedRepository extends FakeIssueRepository {
  new() : super(now: () => DateTime.utc(2026, 1, 15, 12));

  /// Called instead of the canned page when set.
  Future<CommentPage> Function(String? before, int limit)? onComments;

  /// Holds [postComment] until completed.
  Future<void>? postGate;

  @override
  Future<CommentPage> fetchComments(
    String issueId, {
    String? before,
    int limit = kCommentPageSize,
  }) {
    final handler = onComments;
    if (handler != null) return handler(before, limit);
    return super.fetchComments(issueId, before: before, limit: limit);
  }

  @override
  Future<IssueComment> postComment(
    String issueId, {
    required String body,
    required String clientRequestId,
  }) async {
    await postGate;
    return await super.postComment(
      issueId,
      body: body,
      clientRequestId: clientRequestId,
    );
  }
}

IssueComment comment(int i, {bool deleted = false, String? requestId}) =>
    IssueComment(
      id: 'c$i',
      body: 'body $i',
      authorKind: CommentAuthorKind.agent,
      deleted: deleted,
      clientRequestId: requestId,
      createdAt: DateTime.utc(2026).add(Duration(hours: i)),
    );

const testIssue = Issue(id: 'issue-1', identifier: 'T-1', title: 'T');

({ProviderContainer container, ScriptedRepository repo}) setUpThread({
  List<IssueComment>? comments,
}) {
  final repo = ScriptedRepository()
    ..issue = testIssue
    ..thread = comments ?? [for (var i = 0; i < 6; i++) comment(i)];
  var n = 0;
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      issueRepositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 15, 12)),
      clientRequestIdProvider.overrideWithValue(() => 'req-${++n}'),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

Future<IssueThreadState> loaded(ProviderContainer c) async {
  final sub = c.listen(issueThreadProvider('T-1'), (_, _) {});
  addTearDown(sub.close);
  for (var i = 0; i < 20 && sub.read().loading; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return sub.read();
}

void main() {
  group('loading and paging', () {
    test('loads the issue and the newest page, oldest first', () async {
      final t = setUpThread();
      final state = await loaded(t.container);

      expect(state.issue?.identifier, 'T-1');
      expect(state.comments.map((c) => c.id), [
        'c0', 'c1', 'c2', 'c3', 'c4', 'c5', //
      ]);
      expect(state.hasEarlier, isFalse);
      expect(state.error, isNull);
      expect(state.lastUpdated, DateTime.utc(2026, 1, 15, 12));
    });

    test('100+ comments load in pages with a Load earlier cursor', () async {
      final t = setUpThread(
        comments: [for (var i = 0; i < 130; i++) comment(i)],
      );
      final first = await loaded(t.container);
      expect(first.comments, hasLength(50));
      expect(first.comments.first.id, 'c80');
      expect(first.comments.last.id, 'c129');
      expect(first.hasEarlier, isTrue);

      final notifier = t.container.read(issueThreadProvider('T-1').notifier);
      await notifier.loadEarlier();
      var s = t.container.read(issueThreadProvider('T-1'));
      expect(s.comments, hasLength(100));
      expect(s.comments.first.id, 'c30');
      expect(s.comments.map((c) => c.id).toSet(), hasLength(100));
      expect(s.hasEarlier, isTrue);

      await notifier.loadEarlier();
      s = t.container.read(issueThreadProvider('T-1'));
      expect(s.comments, hasLength(130));
      expect(s.comments.first.id, 'c0');
      expect(s.hasEarlier, isFalse);
    });

    test('a deleted anchor re-anchors on the next held comment', () async {
      final all = [for (var i = 0; i < 130; i++) comment(i)];
      final t = setUpThread(comments: all);
      await loaded(t.container);
      // c80 (the anchor) is gone on the server: the server answers an unknown
      // anchor with an empty list.
      final remaining = [...all]..removeWhere((c) => c.id == 'c80');
      t.repo.thread = remaining;

      await t.container.read(issueThreadProvider('T-1').notifier).loadEarlier();
      final s = t.container.read(issueThreadProvider('T-1'));

      expect(s.earlierError, isNull);
      expect(s.loadingEarlier, isFalse);
      expect(s.comments.any((c) => c.id == 'c80'), isFalse);
      // It re-anchored on c81 and loaded the page older than it.
      expect(s.comments.first.id, 'c30');
      expect(s.comments.length, greaterThan(50));
      // The held page is kept, not replaced.
      expect(s.comments.last.id, 'c129');
      expect(s.hasEarlier, isTrue);
    });

    test('450+ held comments survive a missing anchor', () async {
      final all = [for (var i = 0; i < 700; i++) comment(i)];
      final t = setUpThread(comments: all);
      await loaded(t.container);
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);
      for (var i = 0; i < 8; i++) {
        await notifier.loadEarlier();
      }
      var s = t.container.read(issueThreadProvider('T-1'));
      expect(s.comments, hasLength(450));
      expect(s.comments.first.id, 'c250');
      expect(s.hasEarlier, isTrue);

      // The oldest held anchor is gone on the server; older comments remain.
      t.repo.thread = [...all]..removeWhere((c) => c.id == 'c250');
      await notifier.loadEarlier();
      s = t.container.read(issueThreadProvider('T-1'));
      expect(s.earlierError, isNull);
      expect(s.comments.any((c) => c.id == 'c250'), isFalse);
      expect(
        s.hasEarlier,
        isTrue,
        reason: 'the 500-comment cap must not look like the end',
      );

      // Keep loading to the true start: no comment is left unreachable.
      var guard = 0;
      while (t.container.read(issueThreadProvider('T-1')).hasEarlier &&
          guard < 20) {
        guard++;
        await notifier.loadEarlier();
      }
      s = t.container.read(issueThreadProvider('T-1'));
      expect(s.hasEarlier, isFalse);
      expect(s.comments.first.id, 'c0');
      expect(s.comments, hasLength(699));
    });

    test('a deleted comment is held for paging but not shown', () async {
      final t = setUpThread(
        comments: [comment(0), comment(1, deleted: true), comment(2)],
      );
      final s = await loaded(t.container);
      expect(s.comments, hasLength(3));
      expect(s.visibleComments.map((c) => c.id), ['c0', 'c2']);
    });

    test(
      'a failed Load earlier keeps the list and reports the error',
      () async {
        final t = setUpThread(
          comments: [for (var i = 0; i < 80; i++) comment(i)],
        );
        await loaded(t.container);
        t.repo.failWith = const Offline();
        await t.container
            .read(issueThreadProvider('T-1').notifier)
            .loadEarlier();
        final s = t.container.read(issueThreadProvider('T-1'));
        expect(s.comments, hasLength(50));
        expect(s.earlierError, isA<Offline>());
        expect(s.hasEarlier, isTrue);
      },
    );

    test('refresh adds new comments and keeps loaded earlier pages', () async {
      final all = [for (var i = 0; i < 80; i++) comment(i)];
      final t = setUpThread(comments: all);
      await loaded(t.container);
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);
      await notifier.loadEarlier();
      expect(
        t.container.read(issueThreadProvider('T-1')).comments,
        hasLength(80),
      );

      t.repo.thread = [...all, comment(80), comment(81)];
      await notifier.refresh();
      final s = t.container.read(issueThreadProvider('T-1'));
      expect(s.comments, hasLength(82));
      expect(s.comments.first.id, 'c0');
      expect(s.comments.last.id, 'c81');
      expect(s.hasEarlier, isFalse);
    });

    test(
      'a refresh that finds a gap replaces the list with the newest page',
      () async {
        final all = [for (var i = 0; i < 60; i++) comment(i)];
        final t = setUpThread(comments: all);
        await loaded(t.container);
        t.repo.thread = [for (var i = 0; i < 200; i++) comment(i)];
        await t.container.read(issueThreadProvider('T-1').notifier).refresh();
        final s = t.container.read(issueThreadProvider('T-1'));
        expect(s.comments, hasLength(50));
        expect(s.comments.first.id, 'c150');
        expect(s.hasEarlier, isTrue);
      },
    );

    test(
      'a refresh drops a comment that was deleted inside the window',
      () async {
        final all = [for (var i = 0; i < 6; i++) comment(i)];
        final t = setUpThread(comments: all);
        await loaded(t.container);
        t.repo.thread = [...all]..removeAt(3);
        await t.container.read(issueThreadProvider('T-1').notifier).refresh();
        final ids = t.container
            .read(issueThreadProvider('T-1'))
            .comments
            .map((c) => c.id);
        expect(ids, ['c0', 'c1', 'c2', 'c4', 'c5']);
      },
    );

    test('a failed first load reports the error and Retry recovers', () async {
      final t = setUpThread();
      t.repo.failWith = const Server(500);
      final failed = await loaded(t.container);
      expect(failed.issue, isNull);
      expect(failed.error, isA<Server>());

      t.repo.failWith = null;
      await t.container.read(issueThreadProvider('T-1').notifier).refresh();
      final ok = t.container.read(issueThreadProvider('T-1'));
      expect(ok.error, isNull);
      expect(ok.issue, isNotNull);
    });

    test('a failed refresh keeps the data and sets the stale error', () async {
      final t = setUpThread();
      await loaded(t.container);
      t.repo.failWith = const Offline();
      await t.container.read(issueThreadProvider('T-1').notifier).refresh();
      final s = t.container.read(issueThreadProvider('T-1'));
      expect(s.issue, isNotNull);
      expect(s.comments, hasLength(6));
      expect(s.error, isA<Offline>());
    });

    test('there is no polling: nothing is fetched on its own', () async {
      final t = setUpThread();
      await loaded(t.container);
      final fetches = t.repo.commentFetches;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(t.repo.commentFetches, fetches);
    });
  });

  group('sending a reply', () {
    test('shows pending at once, then the confirmed comment', () async {
      final t = setUpThread();
      await loaded(t.container);
      final gate = Completer<void>();
      t.repo.postGate = gate.future;
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);

      final sent = notifier.send('Hello there').done;
      var s = t.container.read(issueThreadProvider('T-1'));
      expect(s.pending, hasLength(1));
      expect(s.pending.single.sending, isTrue);
      expect(s.pending.single.id, 'req-1');
      expect(s.sendInFlight, isTrue);

      gate.complete();
      await sent;
      s = t.container.read(issueThreadProvider('T-1'));
      expect(s.pending, isEmpty);
      expect(s.comments.last.body, 'Hello there');
      expect(t.repo.postedBodies, ['Hello there']);
    });

    test('empty and whitespace-only replies are not sent', () async {
      final t = setUpThread();
      await loaded(t.container);
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);
      expect(notifier.send('').started, isFalse);
      expect(notifier.send('  \n\t ').started, isFalse);
      expect(t.repo.postedBodies, isEmpty);
      expect(t.container.read(issueThreadProvider('T-1')).pending, isEmpty);
    });

    test(
      'one tap is one request: a second send waits while one is in flight',
      () async {
        final t = setUpThread();
        await loaded(t.container);
        final gate = Completer<void>();
        t.repo.postGate = gate.future;
        final notifier = t.container.read(issueThreadProvider('T-1').notifier);

        final first = notifier.send('one').done;
        expect(notifier.send('two').started, isFalse);
        gate.complete();
        await first;
        expect(t.repo.postedBodies, ['one']);
      },
    );

    test(
      'failure keeps the text as "Not sent" and Retry reuses body and id',
      () async {
        final t = setUpThread();
        await loaded(t.container);
        final notifier = t.container.read(issueThreadProvider('T-1').notifier);
        t.repo.failNextPost = const Offline();

        await notifier.send('  Keep me  ').done;
        var s = t.container.read(issueThreadProvider('T-1'));
        expect(s.pending.single.failed, isTrue);
        expect(s.pending.single.error, isA<Offline>());
        expect(s.pending.single.draft, '  Keep me  ');
        expect(s.comments, hasLength(6));

        await notifier.retry('req-1');
        s = t.container.read(issueThreadProvider('T-1'));
        expect(s.pending, isEmpty);
        expect(t.repo.postedBodies, ['Keep me']);
        // No new id was made for the retry.
        expect(s.comments.last.clientRequestId, 'req-1');
      },
    );

    test('retry after a lost answer does not duplicate the comment', () async {
      final t = setUpThread();
      await loaded(t.container);
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);

      // The server got the first request, but the answer never arrived.
      await t.repo.postComment(
        'issue-1',
        body: 'Lost',
        clientRequestId: 'req-1',
      );
      t.repo.failNextPost = const TimedOut();
      await notifier.send('Lost').done;
      expect(
        t.container.read(issueThreadProvider('T-1')).pending.single.failed,
        isTrue,
      );

      await notifier.retry('req-1');
      final s = t.container.read(issueThreadProvider('T-1'));
      expect(t.repo.postedBodies, ['Lost']);
      expect(s.comments.where((c) => c.body == 'Lost'), hasLength(1));
      expect(s.pending, isEmpty);
    });

    test('an edited retry is a new request with a new id', () async {
      final t = setUpThread();
      await loaded(t.container);
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);
      t.repo.failNextPost = const Server(500);

      await notifier.send('first draft').done;
      final edited = await notifier.edit('req-1');
      expect(edited.outcome, EditOutcome.editing);
      expect(edited.reply?.draft, 'first draft');
      expect(t.container.read(issueThreadProvider('T-1')).pending, isEmpty);

      await notifier.send('second draft').done;
      final s = t.container.read(issueThreadProvider('T-1'));
      expect(s.comments.last.clientRequestId, 'req-2');
      expect(t.repo.postedBodies, ['second draft']);
    });

    test(
      'Edit after a lost answer reconciles the comment instead of posting it',
      () async {
        final t = setUpThread();
        await loaded(t.container);
        final notifier = t.container.read(issueThreadProvider('T-1').notifier);

        // The server stored the reply, then its answer was lost.
        await t.repo.postComment(
          'issue-1',
          body: 'Lost',
          clientRequestId: 'req-1',
        );
        t.repo.failNextPost = const TimedOut();
        await notifier.send('Lost').done;
        expect(
          t.container.read(issueThreadProvider('T-1')).pending.single.uncertain,
          isTrue,
        );

        final edited = await notifier.edit('req-1');
        final s = t.container.read(issueThreadProvider('T-1'));
        expect(edited.outcome, EditOutcome.delivered);
        expect(edited.reply, isNull);
        expect(s.pending, isEmpty);
        expect(s.comments.where((c) => c.body == 'Lost'), hasLength(1));
        expect(t.repo.postedBodies, ['Lost']);
      },
    );

    test('Edit finds a stored reply pushed off the newest page', () async {
      final older = [for (var i = 0; i < 10; i++) comment(i)];
      final t = setUpThread(comments: older);
      await loaded(t.container);
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);

      // The server stored the reply, then its answer was lost and enough
      // comments arrived to push it off the newest page.
      await t.repo.postComment(
        'issue-1',
        body: 'Lost',
        clientRequestId: 'req-1',
      );
      t.repo.thread = [...older, for (var i = 0; i < 60; i++) comment(100 + i)];
      t.repo.failNextPost = const TimedOut();
      await notifier.send('Lost').done;
      expect(
        t.container.read(issueThreadProvider('T-1')).pending.single.uncertain,
        isTrue,
      );

      final edited = await notifier.edit('req-1');
      final s = t.container.read(issueThreadProvider('T-1'));
      expect(edited.outcome, EditOutcome.delivered);
      expect(edited.reply, isNull);
      expect(s.pending, isEmpty);
      expect(
        s.comments.where((c) => c.clientRequestId == 'req-1'),
        hasLength(1),
      );
    });

    test(
      'Edit warns when the reply may be deeper than the scan window',
      () async {
        final older = [for (var i = 0; i < 10; i++) comment(i)];
        final t = setUpThread(comments: older);
        await loaded(t.container);
        final notifier = t.container.read(issueThreadProvider('T-1').notifier);

        await t.repo.postComment(
          'issue-1',
          body: 'Lost',
          clientRequestId: 'req-1',
        );
        t.repo.thread = [
          ...older,
          for (var i = 0; i < 560; i++) comment(1000 + i),
        ];
        t.repo.failNextPost = const TimedOut();
        await notifier.send('Lost').done;

        final edited = await notifier.edit('req-1');
        final s = t.container.read(issueThreadProvider('T-1'));
        expect(edited.outcome, EditOutcome.unresolved);
        expect(edited.reply?.id, 'req-1');
        expect(s.pending, hasLength(1));
        expect(s.comments.where((c) => c.clientRequestId == 'req-1'), isEmpty);
      },
    );

    test('Edit is unresolved when the older anchor is gone', () async {
      final t = setUpThread();
      await loaded(t.container);
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);

      // The server stored the reply, then its answer was lost.
      t.repo.failNextPost = const TimedOut();
      await notifier.send('Lost').done;
      expect(
        t.container.read(issueThreadProvider('T-1')).pending.single.uncertain,
        isTrue,
      );

      // The newest page still promises older comments, but the anchor it
      // names was deleted, so the older-page read answers an empty page with
      // `hasEarlier: false` (ADR 0005 decision 2). The reply may be there.
      t.repo.onComments = (before, limit) async => before == null
          ? CommentPage(comments: [comment(0)], hasEarlier: true)
          : const CommentPage(comments: [], hasEarlier: false);

      final edited = await notifier.edit('req-1');
      final s = t.container.read(issueThreadProvider('T-1'));
      expect(edited.outcome, EditOutcome.unresolved);
      expect(edited.reply?.id, 'req-1');
      expect(s.pending, hasLength(1));
    });

    test('a failed reconciliation is unresolved and keeps the reply', () async {
      final t = setUpThread();
      await loaded(t.container);
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);
      t.repo.failNextPost = const TimedOut();
      await notifier.send('maybe').done;
      t.repo.failWith = const Offline();

      final edited = await notifier.edit('req-1');
      final s = t.container.read(issueThreadProvider('T-1'));
      expect(edited.outcome, EditOutcome.unresolved);
      expect(edited.reply?.id, 'req-1');
      expect(s.pending, hasLength(1));
    });

    test('a definite failure is safe to edit without a read', () async {
      final t = setUpThread();
      await loaded(t.container);
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);
      t.repo.failNextPost = const Forbidden('Replies are closed');
      await notifier.send('nope').done;
      final fetches = t.repo.commentFetches;

      final edited = await notifier.edit('req-1');
      expect(edited.outcome, EditOutcome.editing);
      expect(t.repo.commentFetches, fetches);
      expect(t.container.read(issueThreadProvider('T-1')).pending, isEmpty);
    });

    test(
      'the same id with another body is a 409, never an overwrite',
      () async {
        final t = setUpThread();
        await loaded(t.container);
        await t.repo.postComment('issue-1', body: 'a', clientRequestId: 'x');
        await expectLater(
          t.repo.postComment('issue-1', body: 'b', clientRequestId: 'x'),
          throwsA(isA<Server>().having((e) => e.status, 'status', 409)),
        );
      },
    );

    test('a 403 keeps the text and does not change the thread', () async {
      final t = setUpThread();
      await loaded(t.container);
      t.repo.failNextPost = const Forbidden('Not allowed to comment');
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);
      await notifier.send('hi').done;
      final s = t.container.read(issueThreadProvider('T-1'));
      expect(s.pending.single.error, isA<Forbidden>());
      expect(s.comments, hasLength(6));
    });

    test('a refresh drops a pending reply the server already lists', () async {
      final t = setUpThread();
      await loaded(t.container);
      final notifier = t.container.read(issueThreadProvider('T-1').notifier);
      t.repo.failNextPost = const TimedOut();
      await notifier.send('hello').done;
      expect(
        t.container.read(issueThreadProvider('T-1')).pending,
        hasLength(1),
      );

      t.repo.thread = [...t.repo.thread!, comment(9, requestId: 'req-1')];
      await notifier.refresh();
      final s = t.container.read(issueThreadProvider('T-1'));
      expect(s.pending, isEmpty);
      expect(s.comments.last.id, 'c9');
    });

    test('picked mentions are sent as agent links', () async {
      final t = setUpThread();
      await loaded(t.container);
      await t.container
          .read(issueThreadProvider('T-1').notifier)
          .send(
            '@Tester Example look',
            mentions: {'Tester Example': 'agent-qa'},
          )
          .done;
      expect(t.repo.postedBodies, ['[@Tester Example](agent://agent-qa) look']);
    });
  });
}
