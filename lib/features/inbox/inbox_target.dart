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
/// Approvals open S4. Every other kind keeps the PR 1 stopgap and opens its
/// Paperclip page. Only the signed-in host is used; [webUrlFor] rejects any
/// other URL the server might send.
AttentionTarget? itemTarget(AttentionItem item, {required Uri baseUrl}) {
  if (item.sourceKind == SourceKind.approval) {
    final id = _approvalId(item);
    if (id != null) {
      return AttentionRoute(location: AppRoutes.approval(id), item: item);
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
