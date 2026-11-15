import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, NotifierProviderFamily;
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/agent.dart';
import 'package:paperplane/api/models/issue.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/core/uuid.dart';
import 'package:paperplane/data/issue_repository.dart';
import 'package:paperplane/features/issues/mentions.dart';

/// Makes the `clientRequestId` of a send. Tests override it.
final clientRequestIdProvider = Provider<String Function()>((ref) => newUuidV4);

/// A reply the user sent that the server has not confirmed yet.
@immutable
class PendingComment {
  /// Creates the value.
  const new({
    required this.id,
    required this.body,
    required this.draft,
    this.mentions = const {},
    this.sending = true,
    this.error,
  });

  /// The `clientRequestId`. Kept for every retry.
  final String id;

  /// Exact body sent to the server. Never recomputed: a retry with the same
  /// id and another body would be a 409.
  final String body;

  /// What the user typed, for "Edit".
  final String draft;

  /// Agents picked from the sheet, display name to id, for "Edit".
  final Map<String, String> mentions;

  /// True while the request is in flight.
  final bool sending;

  /// Why the last attempt failed. Null while sending.
  final ApiError? error;

  /// True when the last attempt failed ("Not sent — Retry").
  bool get failed => !sending && error != null;

  /// Copy with new send state.
  PendingComment copyWith({bool? sending, ApiError? error}) => PendingComment(
    id: id,
    body: body,
    draft: draft,
    mentions: mentions,
    sending: sending ?? this.sending,
    error: sending ?? false ? null : (error ?? this.error),
  );
}

/// Everything S6 shows for one issue.
@immutable
class IssueThreadState {
  /// Creates the state.
  const new({
    this.issue,
    this.comments = const [],
    this.hasEarlier = false,
    this.loading = true,
    this.refreshing = false,
    this.loadingEarlier = false,
    this.error,
    this.earlierError,
    this.lastUpdated,
    this.pending = const [],
  });

  /// Header and description. Null until the first load succeeds.
  final Issue? issue;

  /// Loaded comments, oldest first, deleted ones included (they can anchor a
  /// page). Use [visibleComments] to show.
  final List<IssueComment> comments;

  /// True when older comments exist on the server.
  final bool hasEarlier;

  /// True until the first load ends.
  final bool loading;

  /// True while a refresh runs.
  final bool refreshing;

  /// True while an earlier page loads.
  final bool loadingEarlier;

  /// Last failed load or refresh. With [issue] set it is a stale-data banner.
  final ApiError? error;

  /// Last failed "Load earlier".
  final ApiError? earlierError;

  /// When the data was fetched.
  final DateTime? lastUpdated;

  /// Replies not yet confirmed, oldest first.
  final List<PendingComment> pending;

  /// Comments to draw: not deleted.
  List<IssueComment> get visibleComments => [
    for (final c in comments)
      if (!c.deleted) c,
  ];

  /// True while a reply is in flight (PRD G6: one write at a time).
  bool get sendInFlight => pending.any((p) => p.sending);

  /// Copy with changes. Pass [clearError] / [clearEarlierError] to reset.
  IssueThreadState copyWith({
    Issue? issue,
    List<IssueComment>? comments,
    bool? hasEarlier,
    bool? loading,
    bool? refreshing,
    bool? loadingEarlier,
    ApiError? error,
    bool clearError = false,
    ApiError? earlierError,
    bool clearEarlierError = false,
    DateTime? lastUpdated,
    List<PendingComment>? pending,
  }) => IssueThreadState(
    issue: issue ?? this.issue,
    comments: comments ?? this.comments,
    hasEarlier: hasEarlier ?? this.hasEarlier,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingEarlier: loadingEarlier ?? this.loadingEarlier,
    error: clearError ? null : (error ?? this.error),
    earlierError: clearEarlierError
        ? null
        : (earlierError ?? this.earlierError),
    lastUpdated: lastUpdated ?? this.lastUpdated,
    pending: pending ?? this.pending,
  );
}

/// Loads, pages and writes one issue thread.
///
/// There is no polling (PRD S6 AC7): the thread is read on open, on
/// pull-to-refresh and when the user taps Retry.
class IssueThread extends Notifier<IssueThreadState> {
  /// Creates the controller for [issueId] (an id or an identifier).
  new(this.issueId);

  /// What the route carried.
  final String issueId;

  @override
  IssueThreadState build() {
    unawaited(
      Future.microtask(() {
        if (ref.mounted) unawaited(_load(initial: true));
      }),
    );
    return const IssueThreadState();
  }

  /// Pull-to-refresh and Retry.
  Future<void> refresh() => _load(initial: state.issue == null);

  Future<void> _load({required bool initial}) async {
    if (state.refreshing) return;
    final repository = ref.read(issueRepositoryProvider);
    state = state.copyWith(
      refreshing: true,
      loading: initial,
      clearError: true,
    );
    try {
      final issueCall = repository.fetchIssue(issueId);
      final commentsCall = repository.fetchComments(issueId);
      // If the issue call fails first, the comments call may still fail later;
      // observe it so that is not an unhandled error.
      unawaited(commentsCall.then((_) {}, onError: (_) {}));
      final loadedIssue = await issueCall;
      final page = await commentsCall;
      if (!ref.mounted) return;
      final merged = _mergeLatest(state, page);
      state = state.copyWith(
        issue: loadedIssue,
        comments: merged.comments,
        hasEarlier: merged.hasEarlier,
        loading: false,
        refreshing: false,
        lastUpdated: ref.read(clockProvider)(),
        pending: _withoutConfirmed(state.pending, merged.comments),
        clearEarlierError: true,
      );
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, refreshing: false, error: error);
    }
  }

  /// "Load earlier": the page just older than the oldest comment held.
  Future<void> loadEarlier() async {
    if (state.loadingEarlier || !state.hasEarlier || state.comments.isEmpty) {
      return;
    }
    final repository = ref.read(issueRepositoryProvider);
    final anchor = state.comments.first.id;
    state = state.copyWith(loadingEarlier: true, clearEarlierError: true);
    try {
      var page = await repository.fetchComments(issueId, before: anchor);
      if (!ref.mounted) return;
      if (page.comments.isEmpty) {
        // The server answers an anchor it no longer has (deleted) with an
        // empty list, which looks like "no more". Read the newest comments
        // again, deep enough to cover what we hold plus one more page.
        page = await repository.fetchComments(
          issueId,
          limit: state.comments.length + kCommentPageSize,
        );
        if (!ref.mounted) return;
        state = state.copyWith(
          comments: page.comments,
          hasEarlier: page.hasEarlier,
          loadingEarlier: false,
          pending: _withoutConfirmed(state.pending, page.comments),
        );
        return;
      }
      final known = {for (final c in state.comments) c.id};
      state = state.copyWith(
        comments: [
          for (final c in page.comments)
            if (!known.contains(c.id)) c,
          ...state.comments,
        ],
        hasEarlier: page.hasEarlier,
        loadingEarlier: false,
      );
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loadingEarlier: false, earlierError: error);
    }
  }

  /// Sends [text] as a reply. [mentions] maps the display name of each agent
  /// picked from the sheet to its id.
  ///
  /// The reply shows at the bottom at once as pending, so `started` is known
  /// right away and `done` completes when the server has answered. `started`
  /// is false when nothing was sent: empty or whitespace-only text (AC5), no
  /// issue loaded, or another send in flight (G6).
  ({bool started, Future<void> done}) send(
    String text, {
    Map<String, String> mentions = const {},
  }) {
    final loaded = state.issue;
    final body = buildCommentBody(text, mentions);
    if (body.isEmpty || loaded == null || state.sendInFlight) {
      return (started: false, done: Future.value());
    }
    final pending = PendingComment(
      id: ref.read(clientRequestIdProvider)(),
      body: body,
      draft: text,
      mentions: mentions,
    );
    state = state.copyWith(pending: [...state.pending, pending]);
    return (started: true, done: _post(pending, loaded.id));
  }

  /// "Not sent — Retry": the same body with the same `clientRequestId`.
  Future<void> retry(String pendingId) async {
    final loaded = state.issue;
    if (loaded == null || state.sendInFlight) return;
    final index = state.pending.indexWhere((p) => p.id == pendingId);
    if (index < 0 || !state.pending[index].failed) return;
    final next = state.pending[index].copyWith(sending: true);
    state = state.copyWith(pending: _replace(state.pending, next));
    await _post(next, loaded.id);
  }

  /// Removes a failed reply, for "Edit" (the caller puts [PendingComment.draft]
  /// back in the composer) and "Discard". An edited text gets a new id when it
  /// is sent again.
  PendingComment? discard(String pendingId) {
    for (final p in state.pending) {
      if (p.id == pendingId && !p.sending) {
        state = state.copyWith(
          pending: [
            for (final q in state.pending)
              if (q.id != pendingId) q,
          ],
        );
        return p;
      }
    }
    return null;
  }

  Future<void> _post(PendingComment pending, String issueDbId) async {
    final repository = ref.read(issueRepositoryProvider);
    try {
      final comment = await repository.postComment(
        issueDbId,
        body: pending.body,
        clientRequestId: pending.id,
      );
      if (!ref.mounted) return;
      final known = {for (final c in state.comments) c.id};
      state = state.copyWith(
        comments: comment.id.isEmpty || known.contains(comment.id)
            ? null
            : [...state.comments, comment],
        pending: [
          for (final p in state.pending)
            if (p.id != pending.id) p,
        ],
      );
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        pending: _replace(
          state.pending,
          pending.copyWith(sending: false, error: error),
        ),
      );
    }
  }

  static List<PendingComment> _replace(
    List<PendingComment> list,
    PendingComment next,
  ) => [
    for (final p in list)
      if (p.id == next.id) next else p,
  ];

  /// Drops replies the server already lists (a send whose answer was lost).
  static List<PendingComment> _withoutConfirmed(
    List<PendingComment> pending,
    List<IssueComment> comments,
  ) {
    final confirmed = {
      for (final c in comments)
        if (c.clientRequestId != null) c.clientRequestId,
    };
    return [
      for (final p in pending)
        if (p.sending || !confirmed.contains(p.id)) p,
    ];
  }

  /// Combines a fresh newest page with what is already held.
  ///
  /// Overlap means the held comments are still valid: take the page's version
  /// of each comment in it and keep the older ones. No overlap (a gap, or the
  /// first load) replaces everything with the page.
  static ({List<IssueComment> comments, bool hasEarlier}) _mergeLatest(
    IssueThreadState current,
    CommentPage page,
  ) {
    if (current.comments.isEmpty) {
      return (comments: page.comments, hasEarlier: page.hasEarlier);
    }
    final fresh = {for (final c in page.comments) c.id: c};
    final overlaps = current.comments.any((c) => fresh.containsKey(c.id));
    if (!overlaps) {
      return (comments: page.comments, hasEarlier: page.hasEarlier);
    }
    final heldIds = {for (final c in current.comments) c.id};
    final oldestFresh = page.comments.isEmpty ? null : page.comments.first.id;
    final out = <IssueComment>[];
    for (final c in current.comments) {
      // A held comment inside the fresh window that the server no longer
      // returns was removed there.
      if (fresh.containsKey(c.id)) {
        out.add(fresh[c.id]!);
      } else if (!_insideWindow(c, current.comments, oldestFresh)) {
        out.add(c);
      }
    }
    out.addAll(page.comments.where((c) => !heldIds.contains(c.id)));
    return (comments: out, hasEarlier: current.hasEarlier);
  }

  static bool _insideWindow(
    IssueComment c,
    List<IssueComment> held,
    String? oldestFresh,
  ) {
    if (oldestFresh == null) return false;
    final at = held.indexWhere((h) => h.id == c.id);
    final from = held.indexWhere((h) => h.id == oldestFresh);
    return from >= 0 && at > from;
  }
}

/// The thread controller of one issue.
final NotifierProviderFamily<IssueThread, IssueThreadState, String>
issueThreadProvider = NotifierProvider.autoDispose
    .family<IssueThread, IssueThreadState, String>(IssueThread.new);

/// Agents of the issue's company, for names and the @agent sheet. A failure
/// leaves the thread usable: names fall back to "Agent".
final FutureProviderFamily<List<Agent>, String> threadAgentsProvider =
    FutureProvider.autoDispose.family<List<Agent>, String>(
      (ref, companyId) =>
          ref.watch(agentRepositoryProvider).listAgents(companyId),
    );
