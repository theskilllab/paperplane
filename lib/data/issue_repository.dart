import 'package:flutter/foundation.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/json.dart';
import 'package:paperplane/api/models/issue.dart';

/// Comments per page (PRD S6 AC3).
const int kCommentPageSize = 50;

/// Most comments the server returns for one `limit`, from the Paperclip
/// source. The repository asks for one extra item to detect an earlier page;
/// it must stay at or below this cap or that probe is clipped and the thread
/// looks finished while older comments remain.
const int kCommentServerCap = 500;

/// One page of comments.
@immutable
class CommentPage {
  /// Creates a page.
  const new({required this.comments, required this.hasEarlier});

  /// Comments oldest to newest. May hold deleted ones: a deleted comment can
  /// still be the cursor of the next page.
  final List<IssueComment> comments;

  /// True when older comments exist beyond this page.
  final bool hasEarlier;
}

/// Reads an issue and its thread, and writes a reply (screen S6).
abstract interface class IssueRepository {
  /// `GET /issues/{idOrIdentifier}`.
  Future<Issue> fetchIssue(String issueId);

  /// The newest [limit] comments when [before] is null, otherwise the
  /// [limit] comments just older than the comment with id [before].
  ///
  /// Oldest to newest in the answer.
  Future<CommentPage> fetchComments(
    String issueId, {
    String? before,
    int limit = kCommentPageSize,
  });

  /// `POST /issues/{id}/comments`.
  ///
  /// The server de-duplicates on [clientRequestId]: the same id with the same
  /// [body] returns the comment that already exists; the same id with another
  /// body is a 409. A retry of a failed send must therefore reuse both.
  Future<IssueComment> postComment(
    String issueId, {
    required String body,
    required String clientRequestId,
  });
}

/// [IssueRepository] over HTTP.
class HttpIssueRepository implements IssueRepository {
  /// Creates the repository.
  const new(this._client);

  final ApiClient _client;

  @override
  Future<Issue> fetchIssue(String issueId) async {
    final response = await _client.get(
      '/issues/${Uri.encodeComponent(issueId)}',
    );
    return Issue.fromJson(asMap(response.data));
  }

  @override
  Future<CommentPage> fetchComments(
    String issueId, {
    String? before,
    int limit = kCommentPageSize,
  }) async {
    // The server pages newest first. `after` is a cursor in that order, so it
    // returns the comments older than the anchor. One extra item tells us
    // whether another page exists. Keep the probe inside the server cap, or a
    // clipped answer would read as "no earlier page".
    final pageSize = limit < kCommentServerCap ? limit : kCommentServerCap - 1;
    final response = await _client.get(
      '/issues/${Uri.encodeComponent(issueId)}/comments',
      query: {'order': 'desc', 'limit': pageSize + 1, 'after': ?before},
    );
    final newestFirst = IssueComment.listFromJson(response.data);
    final hasEarlier = newestFirst.length > pageSize;
    final page = hasEarlier ? newestFirst.sublist(0, pageSize) : newestFirst;
    return CommentPage(
      comments: page.reversed.toList(growable: false),
      hasEarlier: hasEarlier,
    );
  }

  @override
  Future<IssueComment> postComment(
    String issueId, {
    required String body,
    required String clientRequestId,
  }) async {
    final response = await _client.post(
      '/issues/${Uri.encodeComponent(issueId)}/comments',
      body: {'body': body, 'clientRequestId': clientRequestId},
    );
    return IssueComment.fromJson(asMap(response.data));
  }
}
