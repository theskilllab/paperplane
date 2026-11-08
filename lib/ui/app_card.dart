import 'package:flutter/material.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// A bordered surface: `bg`, 1 px `line`, 10 radius, clipped. No shadow.
class AppCard extends StatelessWidget {
  /// Creates a card.
  const new({required this.child, this.padding = EdgeInsets.zero, super.key});

  /// Content.
  final Widget child;

  /// Inner padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pp.bg,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: pp.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md - 1),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A card whose [children] are separated by 1 px `line` dividers.
class AppCardList extends StatelessWidget {
  /// Creates the list.
  const new({required this.children, super.key});

  /// Rows, usually `AppListRow`s.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              ColoredBox(color: pp.line, child: const SizedBox(height: 1)),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Header of a group of rows: upper-case label and a count.
class AppGroupHeader extends StatelessWidget {
  /// Creates the header.
  const new(this.label, {this.count, super.key});

  /// Group name. It is shown in upper case.
  final String label;

  /// Number of items in the group.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return Semantics(
      header: true,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s3,
          Space.s4,
          Space.s2,
        ),
        child: Row(
          children: [
            Text(label.toUpperCase(), style: pp.text.groupHeader),
            if (count != null) ...[
              const SizedBox(width: Space.s2),
              Text('$count', style: pp.text.groupCount),
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of a list: leading widget, a two-line title, a meta line and an
/// optional chevron. Rows grow with the text size instead of truncating.
class AppListRow extends StatelessWidget {
  /// Creates a row.
  const new({
    required this.title,
    this.leading,
    this.meta,
    this.trailing,
    this.onTap,
    this.unread = false,
    this.resolving = false,
    this.chevron = false,
    this.tall = false,
    this.semanticLabel,
    super.key,
  });

  /// Title, two lines at most.
  final String title;

  /// Widget before the title, for example an `AppStatusIcon`.
  final Widget? leading;

  /// Line under the title: id, avatar, name, age.
  final Widget? meta;

  /// Widget at the end, replaced by a spinner while [resolving].
  final Widget? trailing;

  /// Called on tap. Null makes the row inert (for example no `href`).
  final VoidCallback? onTap;

  /// Shows the 8 px unread dot.
  final bool unread;

  /// A decision is being sent for this row: 50% opacity, spinner, no taps.
  final bool resolving;

  /// Shows a chevron at the end.
  final bool chevron;

  /// Minimum height 64 (approval rows) instead of 56.
  final bool tall;

  /// Spoken description of the whole row, for example
  /// "Approval, Hire a support agent, from the CEO, 12 minutes ago".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final tappable = onTap != null && !resolving;

    final end = resolving
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : trailing ??
              (chevron
                  ? AppIcon(AppIconName.chev, size: 18, color: pp.ink3)
                  : null);

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unread)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: pp.accent,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 8),
              ),
            ),
          if (leading != null) ...[
            Padding(padding: const EdgeInsets.only(top: 2), child: leading),
            const SizedBox(width: Space.s3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: pp.text.rowTitle,
                ),
                if (meta != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s1),
                    child: DefaultTextStyle.merge(
                      style: pp.text.micro,
                      child: meta!,
                    ),
                  ),
              ],
            ),
          ),
          if (end != null) ...[
            const SizedBox(width: Space.s3),
            Padding(padding: const EdgeInsets.only(top: 2), child: end),
          ],
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      enabled: tappable,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Opacity(
        opacity: resolving ? 0.5 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: tappable ? onTap : null,
            highlightColor: pp.panel,
            hoverColor: pp.panel,
            splashFactory: NoSplash.splashFactory,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: tall ? Sizes.approvalRowH : Sizes.rowH,
              ),
              child: row,
            ),
          ),
        ),
      ),
    );
  }
}
