import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/ui/ui.dart';

/// "just now", "12 min ago", "3 h ago" or "2 d ago". Empty without a [time].
String formatAge(DateTime? time, DateTime now) {
  if (time == null) return '';
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

/// The page a row opens in the system browser: [baseUrl] plus the item's
/// server-relative [href].
///
/// Returns null (row not tappable) when [href] is missing, or is anything but
/// a plain absolute path: a full URL or `//host/path` from the server is never
/// followed, so a bad payload cannot send the user to another site.
Uri? webUrlFor(Uri baseUrl, String? href) {
  if (href == null || !href.startsWith('/') || href.startsWith('//')) {
    return null;
  }
  final parsed = Uri.tryParse(href);
  if (parsed == null || parsed.hasScheme || parsed.hasAuthority) return null;
  return Uri(
    scheme: baseUrl.scheme,
    host: baseUrl.host,
    port: baseUrl.hasPort ? baseUrl.port : null,
    path: '${baseUrl.path}${parsed.path}',
    query: parsed.hasQuery ? parsed.query : null,
    fragment: parsed.hasFragment ? parsed.fragment : null,
  );
}

/// Heading of an Inbox group.
String groupLabel(InboxGroup group) => switch (group) {
  InboxGroup.approvals => 'Approvals',
  InboxGroup.questions => 'Questions',
  InboxGroup.needsAttention => 'Needs attention',
};

/// Short name of a kind, for the spoken row label and the meta line.
String kindLabel(SourceKind kind) => switch (kind) {
  SourceKind.approval => 'Approval',
  SourceKind.issueThreadInteraction => 'Question',
  SourceKind.decision => 'Decision',
  SourceKind.joinRequest => 'Join request',
  SourceKind.recoveryAction => 'Recovery',
  SourceKind.productivityReview => 'Productivity review',
  SourceKind.blockerAttention => 'Blocked',
  SourceKind.review => 'Review',
  SourceKind.failedRun => 'Failed run',
  SourceKind.budgetAlert => 'Budget',
  SourceKind.agentErrorAlert => 'Agent error',
  SourceKind.unknown => 'Needs attention',
};

/// Type icon of a kind.
AppIconName kindIcon(SourceKind kind) => switch (kind) {
  SourceKind.approval => AppIconName.shield,
  SourceKind.issueThreadInteraction => AppIconName.send,
  SourceKind.decision => AppIconName.swap,
  SourceKind.joinRequest => AppIconName.userplus,
  SourceKind.recoveryAction => AppIconName.server,
  SourceKind.productivityReview => AppIconName.folder,
  SourceKind.blockerAttention ||
  SourceKind.budgetAlert ||
  SourceKind.agentErrorAlert => AppIconName.alert,
  SourceKind.review => AppIconName.check,
  SourceKind.failedRun => AppIconName.x,
  SourceKind.unknown => AppIconName.link,
};

/// Items the server holds for [group].
///
/// Uses `countsBySourceKind` so the number is right even when the feed was
/// cut at the page limit (feasibility §5 row 3). Falls back to the rows in
/// hand when the server sent no counts.
int groupCount(AttentionFeed feed, InboxGroup group) {
  final shown = feed.inGroup(group).length;
  if (feed.countsBySourceKind.isEmpty) return shown;
  final approvals = feed.countsBySourceKind[SourceKind.approval.wire] ?? 0;
  final questions =
      feed.countsBySourceKind[SourceKind.issueThreadInteraction.wire] ?? 0;
  final count = switch (group) {
    InboxGroup.approvals => approvals,
    InboxGroup.questions => questions,
    InboxGroup.needsAttention => feed.totalCount - approvals - questions,
  };
  return count < shown ? shown : count;
}
