import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// What kind of thing needs the user. The server has 11 kinds; any other
/// value reads as [unknown] and shows as a generic row.
enum SourceKind {
  /// An approval request (`approval`).
  approval('approval'),

  /// A question or confirmation inside an issue thread
  /// (`issue_thread_interaction`).
  issueThreadInteraction('issue_thread_interaction'),

  /// A decision request (`decision`).
  decision('decision'),

  /// Someone asks to join (`join_request`).
  joinRequest('join_request'),

  /// A recovery action (`recovery_action`).
  recoveryAction('recovery_action'),

  /// A productivity review (`productivity_review`).
  productivityReview('productivity_review'),

  /// An issue blocked on the user (`blocker_attention`).
  blockerAttention('blocker_attention'),

  /// Work waiting for review (`review`).
  review('review'),

  /// A run failed (`failed_run`).
  failedRun('failed_run'),

  /// A budget alert (`budget_alert`).
  budgetAlert('budget_alert'),

  /// An agent reports an error (`agent_error_alert`).
  agentErrorAlert('agent_error_alert'),

  /// A kind this app version does not know.
  unknown('');

  new(this.wire);

  /// Value on the wire.
  final String wire;

  /// Parses the wire value; unknown values become [unknown].
  static SourceKind parse(String? value) {
    for (final kind in values) {
      if (kind != unknown && kind.wire == value) return kind;
    }
    return unknown;
  }

  /// The Inbox group the kind belongs to (feasibility §2 row 1).
  InboxGroup get group => switch (this) {
    approval => InboxGroup.approvals,
    issueThreadInteraction => InboxGroup.questions,
    _ => InboxGroup.needsAttention,
  };
}

/// Groups of the Inbox, in display order.
enum InboxGroup {
  /// Approvals.
  approvals,

  /// Questions and confirmations.
  questions,

  /// Everything else; opens in the browser.
  needsAttention,
}

/// The thing an attention item points at.
@immutable
class AttentionSubject {
  /// Creates a subject.
  const new({this.href, this.metadata = const {}});

  /// Parses the `subject` object tolerantly.
  factory fromJson(Map<String, Object?> json) => AttentionSubject(
    href: readNonEmpty(json, 'href'),
    metadata: asMap(json['metadata']),
  );

  /// Server-relative path of the web page, for example
  /// `/ABC/approvals/<id>`. Null means the row is not tappable.
  final String? href;

  /// Kind-specific extras (for approvals, `requestedByAgentId`).
  final Map<String, Object?> metadata;
}

/// One row of the attention feed (`GET /companies/{id}/attention`).
@immutable
class AttentionItem {
  /// Creates an item.
  const new({
    required this.id,
    required this.sourceKind,
    required this.title,
    this.rawSourceKind = '',
    this.summary,
    this.subject = const AttentionSubject(),
    this.originAgentName,
    this.createdAt,
    this.activityAt,
    this.resolverAudience,
    this.inlineResolvable = false,
  });

  /// Parses one item tolerantly.
  factory fromJson(Map<String, Object?> json) {
    final subject = AttentionSubject.fromJson(asMap(json['subject']));
    final raw = readString(json, 'sourceKind') ?? '';
    return AttentionItem(
      id: readString(json, 'id') ?? '',
      sourceKind: SourceKind.parse(raw),
      rawSourceKind: raw,
      title:
          readNonEmpty(json, 'title') ??
          readNonEmpty(asMap(json['subject']), 'title') ??
          '',
      summary: readNonEmpty(json, 'summary') ?? readNonEmpty(json, 'excerpt'),
      subject: subject,
      originAgentName: readNonEmpty(json, 'originAgentName'),
      createdAt: readDate(json, 'createdAt'),
      activityAt: readDate(json, 'activityAt'),
      resolverAudience: readNonEmpty(json, 'resolverAudience'),
      // Absent means "do not decide inline": the server is the authority.
      inlineResolvable: readBool(json, 'inlineResolvable'),
    );
  }

  /// Item id.
  final String id;

  /// Parsed kind.
  final SourceKind sourceKind;

  /// Kind exactly as the server sent it (useful for the generic row).
  final String rawSourceKind;

  /// Headline.
  final String title;

  /// Short excerpt, when the server sends one.
  final String? summary;

  /// Link target and extras.
  final AttentionSubject subject;

  /// Name of the agent that raised it, when the server sends it.
  final String? originAgentName;

  /// When it was created.
  final DateTime? createdAt;

  /// Last activity. Rows sort by this.
  final DateTime? activityAt;

  /// Who may answer (`board`, `any`, ...). Known before opening the item.
  final String? resolverAudience;

  /// False means show the item read-only plus "Open in Paperclip".
  final bool inlineResolvable;

  /// Id of the agent that requested an approval, when present.
  String? get requestedByAgentId =>
      readNonEmpty(subject.metadata, 'requestedByAgentId');
}

/// The attention feed of one company.
@immutable
class AttentionFeed {
  /// Creates a feed.
  const new({
    required this.items,
    required this.totalCount,
    this.countsBySourceKind = const {},
    this.generatedAt,
    this.nextCursor,
  });

  /// Parses the body tolerantly.
  factory fromJson(Map<String, Object?> json) {
    final items = [
      for (final entry in asList(json['items']))
        AttentionItem.fromJson(asMap(entry)),
    ];
    final counts = asMap(json['countsBySourceKind']);
    return AttentionFeed(
      items: items,
      totalCount: readInt(json, 'totalCount', fallback: items.length),
      countsBySourceKind: {
        for (final entry in counts.entries)
          if (entry.value is num) entry.key: (entry.value! as num).toInt(),
      },
      generatedAt: readDate(json, 'generatedAt'),
      nextCursor: readNonEmpty(json, 'nextCursor'),
    );
  }

  /// First page of items, newest activity first.
  final List<AttentionItem> items;

  /// Items on the server. Use this, not `deskBadgeCount`.
  final int totalCount;

  /// Items per wire kind. Use for group counts.
  final Map<String, int> countsBySourceKind;

  /// When the server built the feed.
  final DateTime? generatedAt;

  /// Cursor of the next page. PR 1 does not page.
  final String? nextCursor;

  /// True when the server has more items than [items] holds.
  bool get isTruncated => totalCount > items.length;

  /// Items of one [group], in server order.
  List<AttentionItem> inGroup(InboxGroup group) => [
    for (final item in items)
      if (item.sourceKind.group == group) item,
  ];
}
