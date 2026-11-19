import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// State of an approval on the server.
enum ApprovalStatus {
  /// Waiting for a decision.
  pending('pending'),

  /// The board asked for a revision and the agent resubmitted.
  revisionRequested('revision_requested'),

  /// Approved.
  approved('approved'),

  /// Rejected.
  rejected('rejected'),

  /// Withdrawn by the requester.
  cancelled('cancelled'),

  /// A status this app version does not know.
  unknown('');

  new(this.wire);

  /// Value on the wire.
  final String wire;

  /// Parses the wire value; unknown values become [unknown].
  static ApprovalStatus parse(String? value) {
    for (final status in values) {
      if (status != unknown && status.wire == value) return status;
    }
    return unknown;
  }

  /// True while a decision can still be sent.
  bool get isPending => this == pending || this == revisionRequested;

  /// Short label for a status pill.
  String get label => switch (this) {
    pending => 'Pending',
    revisionRequested => 'Revision requested',
    approved => 'Approved',
    rejected => 'Rejected',
    cancelled => 'Cancelled',
    unknown => 'Unknown',
  };
}

/// One approval (`GET /approvals/{id}`).
@immutable
class Approval {
  /// Creates an approval.
  const new({
    required this.id,
    required this.type,
    required this.status,
    this.companyId = '',
    this.payload = const {},
    this.requestedByAgentId,
    this.requestedByUserId,
    this.decisionNote,
    this.decidedByUserId,
    this.decidedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Parses the body tolerantly.
  factory fromJson(Map<String, Object?> json) {
    final rawType = readString(json, 'type') ?? '';
    return Approval(
      id: readString(json, 'id') ?? '',
      companyId: readString(json, 'companyId') ?? '',
      type: rawType,
      status: ApprovalStatus.parse(readString(json, 'status')),
      payload: asMap(json['payload']),
      requestedByAgentId: readNonEmpty(json, 'requestedByAgentId'),
      requestedByUserId: readNonEmpty(json, 'requestedByUserId'),
      decisionNote: readNonEmpty(json, 'decisionNote'),
      decidedByUserId: readNonEmpty(json, 'decidedByUserId'),
      decidedAt: readDate(json, 'decidedAt'),
      createdAt: readDate(json, 'createdAt'),
      updatedAt: readDate(json, 'updatedAt'),
    );
  }

  /// Approval id.
  final String id;

  /// Company the approval belongs to.
  final String companyId;

  /// Wire type (`hire_agent`, `approve_ceo_strategy`,
  /// `budget_override_required`, `request_board_approval`, or an unknown one).
  final String type;

  /// Current status.
  final ApprovalStatus status;

  /// Free-form request body. Its shape depends on [type].
  final Map<String, Object?> payload;

  /// Agent that asked, when the server sends an id.
  final String? requestedByAgentId;

  /// Board user that asked, when the server sends an id.
  final String? requestedByUserId;

  /// Note the decider wrote, when any.
  final String? decisionNote;

  /// User id of the decider. The approval carries no name.
  final String? decidedByUserId;

  /// When it was decided.
  final DateTime? decidedAt;

  /// When it was created.
  final DateTime? createdAt;

  /// Last change.
  final DateTime? updatedAt;

  /// Copies the approval with a new decision state.
  Approval copyWith({
    ApprovalStatus? status,
    String? decisionNote,
    String? decidedByUserId,
    DateTime? decidedAt,
  }) => Approval(
    id: id,
    companyId: companyId,
    type: type,
    status: status ?? this.status,
    payload: payload,
    requestedByAgentId: requestedByAgentId,
    requestedByUserId: requestedByUserId,
    decisionNote: decisionNote ?? this.decisionNote,
    decidedByUserId: decidedByUserId ?? this.decidedByUserId,
    decidedAt: decidedAt ?? this.decidedAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// True while the request can still be decided.
  bool get isPending => status.isPending;

  /// Title for the screen: the payload's own title, else a readable type.
  String get title =>
      readNonEmpty(payload, 'title') ??
      readNonEmpty(payload, 'name') ??
      readNonEmpty(payload, 'summary') ??
      _typeLabel;

  /// Short summary the server put in the payload, when any.
  String? get summary =>
      readNonEmpty(payload, 'summary') ?? readNonEmpty(payload, 'description');

  /// Types whose payload this app knows how to render in full.
  static const knownTypes = {
    'hire_agent',
    'approve_ceo_strategy',
    'budget_override_required',
  };

  /// True when the app can render the whole body. Unknown types show the raw
  /// summary and the Paperclip link instead (PRD S4 AC8).
  bool get hasKnownBody => knownTypes.contains(type);

  String get _typeLabel => switch (type) {
    'hire_agent' => 'Hire an agent',
    'approve_ceo_strategy' => 'Approve the CEO strategy',
    'budget_override_required' => 'Budget override',
    'request_board_approval' => 'Board approval',
    _ => type.isEmpty ? 'Approval' : _humanize(type),
  };

  static String _humanize(String value) {
    final words = value.replaceAll('_', ' ').trim();
    if (words.isEmpty) return 'Approval';
    return words[0].toUpperCase() + words.substring(1);
  }
}

/// An issue linked to an approval (`GET /approvals/{id}/issues`).
@immutable
class LinkedIssue {
  /// Creates the value.
  const new({
    required this.id,
    required this.identifier,
    required this.title,
    this.status = '',
  });

  /// Parses one issue tolerantly.
  factory fromJson(Map<String, Object?> json) => LinkedIssue(
    id: readString(json, 'id') ?? '',
    identifier: readString(json, 'identifier') ?? '',
    title: readNonEmpty(json, 'title') ?? '',
    status: readString(json, 'status') ?? '',
  );

  /// Issue id.
  final String id;

  /// Human identifier, for example `ABC-12`.
  final String identifier;

  /// Title.
  final String title;

  /// Wire status.
  final String status;
}
