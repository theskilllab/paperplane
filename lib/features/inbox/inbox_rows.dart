import 'package:flutter/material.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/features/inbox/inbox_format.dart';
import 'package:paperplane/ui/ui.dart';

/// One Inbox row: type icon, title, who raised it and how long ago.
///
/// Rows with a web page open it in the browser (the PR 1 stopgap); rows
/// without one are not tappable (S2 AC7).
class AttentionRow extends StatelessWidget {
  /// Creates a row for [item].
  ///
  /// [agentNames] resolves the agent id that approvals carry. [onOpen] is null
  /// when the item has no page to open.
  const new({
    required this.item,
    required this.agentNames,
    required this.now,
    required this.onOpen,
    super.key,
  });

  /// The feed item.
  final AttentionItem item;

  /// Agent id to display name.
  final Map<String, String> agentNames;

  /// The time ages are measured against.
  final DateTime now;

  /// Opens the item's page, or null when it has none.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final kind = item.sourceKind;
    final agentId = item.requestedByAgentId;
    final fromMap = agentId == null ? null : agentNames[agentId];
    final who =
        item.originAgentName ?? (fromMap?.isEmpty ?? true ? null : fromMap);
    final age = formatAge(item.activityAt ?? item.createdAt, now);
    // The "Needs attention" group mixes kinds, so each row names its own.
    final showKind =
        kind.group == InboxGroup.needsAttention && kind != SourceKind.unknown;

    final spoken = [
      kindLabel(kind),
      item.title,
      if (who != null) 'from $who',
      if (age.isNotEmpty) age,
      if (onOpen != null) 'Opens in your browser',
    ].join(', ');

    return AppListRow(
      title: item.title,
      tall: kind == SourceKind.approval,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: pp.panel,
          borderRadius: BorderRadius.circular(9),
        ),
        child: SizedBox.square(
          dimension: 36,
          child: Center(
            child: AppIcon(kindIcon(kind), size: 20, color: pp.ink2),
          ),
        ),
      ),
      meta: _Meta(
        parts: [
          if (showKind) Text(kindLabel(kind)),
          if (who != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppGhostAvatar(agentId ?? who, size: 16),
                const SizedBox(width: Space.s1),
                Flexible(child: Text(who, overflow: TextOverflow.ellipsis)),
              ],
            ),
          if (age.isNotEmpty) Text(age),
        ],
      ),
      trailing: onOpen == null
          ? null
          : AppIcon(AppIconName.link, size: 18, color: pp.ink3),
      onTap: onOpen,
      semanticLabel: spoken,
    );
  }
}

/// The line under a title: [parts] separated by a middle dot. A dot always
/// stays with the part after it, so a wrapped line never starts with one.
class _Meta extends StatelessWidget {
  const new({required this.parts});

  final List<Widget> parts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.s2,
      children: [
        for (var i = 0; i < parts.length; i++)
          if (i == 0)
            parts[i]
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('·'),
                const SizedBox(width: Space.s2),
                Flexible(child: parts[i]),
              ],
            ),
      ],
    );
  }
}
