/// Paths of every route. Screens link with these, never with string literals.
abstract final class AppRoutes {
  /// Start-up while the stored key is read.
  static const splash = '/splash';

  /// S1: connect and sign in.
  static const connect = '/connect';

  /// S2: Inbox (root).
  static const inbox = '/';

  /// S4: approval detail.
  static const approvalPattern = '/approvals/:approvalId';

  /// S4 path for [approvalId].
  static String approval(String approvalId) =>
      '/approvals/${Uri.encodeComponent(approvalId)}';

  /// S5: question or confirmation on an issue thread.
  static const interactionPattern =
      '/issues/:issueId/interactions/:interactionId';

  /// S5 path.
  static String interaction(String issueId, String interactionId) =>
      '/issues/${Uri.encodeComponent(issueId)}'
      '/interactions/${Uri.encodeComponent(interactionId)}';

  /// S7: new issue. Declared before [issuePattern] so `new` is not an id.
  static const newIssue = '/issues/new';

  /// S6: issue and thread.
  static const issuePattern = '/issues/:issueId';

  /// S6 path for [issueId].
  static String issue(String issueId) =>
      '/issues/${Uri.encodeComponent(issueId)}';
}
