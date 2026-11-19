import 'package:flutter/foundation.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/app/routes.dart';
import 'package:paperplane/features/inbox/inbox_format.dart';

/// Where a row in S2 goes.
@immutable
sealed class AttentionTarget {
  const new();
}

/// An in-app screen. The [item] is passed as the route's extra so the screen
/// keeps the server's `inlineResolvable` and title without a second lookup.
final class AttentionRoute extends AttentionTarget {
  /// Creates the target.
  const new({required this.location, required this.item});

  /// Route location, for example `/approvals/appr-1`.
  final String location;

  /// The row that opened it.
  final AttentionItem item;
}

/// A web page in the system browser (the stopgap until that screen lands).
final class AttentionBrowser extends AttentionTarget {
  /// Creates the target.
  const new(this.url);

  /// Page to open.
  final Uri url;
}

/// Where [item] goes, or null when it is not tappable.
///
/// Approvals open S4 and items that link to an issue open S6. Questions keep
/// the browser stopgap until S5 exists, and so does every other kind that does
/// not link to an issue. Only the signed-in host is used; [webUrlFor] rejects
/// any other URL the server might send.
AttentionTarget? itemTarget(AttentionItem item, {required Uri baseUrl}) {
  if (item.sourceKind == SourceKind.approval) {
    final id = _approvalId(item);
    if (id != null) {
      return AttentionRoute(location: AppRoutes.approval(id), item: item);
    }
  }
  if (item.sourceKind != SourceKind.issueThreadInteraction) {
    final id = _issueId(item);
    if (id != null) {
      return AttentionRoute(location: AppRoutes.issue(id), item: item);
    }
  }
  final url = webUrlFor(baseUrl, item.subject.href);
  return url == null ? null : AttentionBrowser(url);
}

/// The approval id in `/{prefix}/approvals/{id}`. The attention item's own id
/// is a different row id, so read the id from the link the server sent.
String? _approvalId(AttentionItem item) {
  final href = item.subject.href;
  if (href == null || !href.startsWith('/') || href.startsWith('//')) {
    return null;
  }
  final uri = Uri.tryParse(href);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final at = segments.lastIndexOf('approvals');
  if (at < 0 || at + 1 >= segments.length) return null;
  final id = segments[at + 1];
  return id.isEmpty ? null : id;
}

/// The issue id or identifier in `/{prefix}/issues/{id}`.
///
/// A fragment or an `interactions` path is an in-thread target, not the issue,
/// so it keeps the stopgap until S5. `new` is S7's route, not an issue.
String? _issueId(AttentionItem item) {
  final href = item.subject.href;
  if (href == null || !href.startsWith('/') || href.startsWith('//')) {
    return null;
  }
  final uri = Uri.tryParse(href);
  if (uri == null || uri.hasScheme || uri.hasAuthority || uri.hasFragment) {
    return null;
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final at = segments.lastIndexOf('issues');
  if (at < 0 || at + 1 >= segments.length) return null;
  if (at + 2 < segments.length && segments[at + 2] == 'interactions') {
    return null;
  }
  final id = segments[at + 1];
  if (id.isEmpty || id == 'new') return null;
  return id;
}
