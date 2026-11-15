import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// Status of an issue. Any value this app does not know reads as [unknown]
/// and shows the server's own text.
enum IssueStatus {
  /// `backlog`.
  backlog('backlog', 'Backlog'),

  /// `todo`.
  todo('todo', 'To do'),

  /// `in_progress`.
  inProgress('in_progress', 'In progress'),

  /// `in_review`.
  inReview('in_review', 'In review'),

  /// `blocked`.
  blocked('blocked', 'Blocked'),

  /// `done`.
  done('done', 'Done'),

  /// `cancelled`.
  cancelled('cancelled', 'Cancelled'),

  /// A status this app version does not know.
  unknown('', 'Unknown');

  new(this.wire, this.label);

  /// Value on the wire.
  final String wire;

  /// Text for the status pill.
  final String label;

  /// Parses the wire value.
  static IssueStatus parse(String? value) {
    for (final status in values) {
      if (status != unknown && status.wire == value) return status;
    }
    return unknown;
  }

  /// True when the issue is finished. Reading still works; a reply is sent
  /// anyway and the server decides.
  bool get isClosed => this == done || this == cancelled;
}

/// The issue header and description (`GET /issues/{id}`).
@immutable
class Issue {
  /// Creates an issue.
  const new({
    required this.id,
    required this.identifier,
    required this.title,
    this.companyId = '',
    this.status = IssueStatus.unknown,
    this.rawStatus = '',
    this.description,
    this.assigneeAgentId,
    this.assigneeUserId,
    this.projectId,
    this.projectName,
  });

  /// Parses the answer tolerantly. The server sends many more fields; only
  /// what S6 shows is read.
  factory fromJson(Map<String, Object?> json) {
    final raw = readString(json, 'status') ?? '';
    return Issue(
      id: readString(json, 'id') ?? '',
      identifier: readString(json, 'identifier') ?? '',
      title: readString(json, 'title') ?? '',
      companyId: readString(json, 'companyId') ?? '',
      status: IssueStatus.parse(raw),
      rawStatus: raw,
      description: readNonEmpty(json, 'description'),
      assigneeAgentId: readNonEmpty(json, 'assigneeAgentId'),
      assigneeUserId: readNonEmpty(json, 'assigneeUserId'),
      projectId: readNonEmpty(json, 'projectId'),
      projectName: readNonEmpty(asMap(json['project']), 'name'),
    );
  }

  /// Server id.
  final String id;

  /// Human id such as `ABC-12`.
  final String identifier;

  /// Title.
  final String title;

  /// Company the issue belongs to.
  final String companyId;

  /// Parsed status.
  final IssueStatus status;

  /// Status as sent, for display when [status] is unknown.
  final String rawStatus;

  /// Markdown description, when set.
  final String? description;

  /// Assigned agent, when the assignee is an agent.
  final String? assigneeAgentId;

  /// Assigned person, when the assignee is a user.
  final String? assigneeUserId;

  /// Project id, when set.
  final String? projectId;

  /// Project name, when the server sent the project.
  final String? projectName;

  /// Text for the status pill.
  String get statusLabel =>
      status == IssueStatus.unknown && rawStatus.isNotEmpty
      ? rawStatus
      : status.label;
}

/// Who wrote a comment.
enum CommentAuthorKind {
  /// An agent.
  agent,

  /// A person.
  user,

  /// Something else (system, or a value this app does not know).
  other,
}

/// One comment of an issue thread.
@immutable
class IssueComment {
  /// Creates a comment.
  const new({
    required this.id,
    required this.body,
    this.authorKind = CommentAuthorKind.other,
    this.authorAgentId,
    this.authorUserId,
    this.createdAt,
    this.deleted = false,
    this.clientRequestId,
  });

  /// Parses one comment tolerantly.
  factory fromJson(Map<String, Object?> json) => IssueComment(
    id: readString(json, 'id') ?? '',
    body: readString(json, 'body') ?? '',
    authorKind: switch (readString(json, 'authorType')) {
      'agent' => CommentAuthorKind.agent,
      'user' => CommentAuthorKind.user,
      _ => CommentAuthorKind.other,
    },
    authorAgentId: readNonEmpty(json, 'authorAgentId'),
    authorUserId: readNonEmpty(json, 'authorUserId'),
    createdAt: readDate(json, 'createdAt'),
    deleted: readString(json, 'deletedAt') != null,
    clientRequestId: readNonEmpty(json, 'clientRequestId'),
  );

  /// Server id. Also the paging cursor.
  final String id;

  /// Markdown body.
  final String body;

  /// Agent, person or other.
  final CommentAuthorKind authorKind;

  /// Writing agent, for agent comments.
  final String? authorAgentId;

  /// Writing person, for user comments.
  final String? authorUserId;

  /// When it was written.
  final DateTime? createdAt;

  /// True when the server marks it deleted. Such a comment is not shown, but
  /// it can still be the paging anchor.
  final bool deleted;

  /// Id the client sent with the write, when the server echoes it.
  final String? clientRequestId;

  /// Parses a JSON array and drops entries without an id.
  static List<IssueComment> listFromJson(Object? json) => [
    for (final entry in asList(json))
      if (IssueComment.fromJson(asMap(entry)) case final c when c.id.isNotEmpty)
        c,
  ];
}
