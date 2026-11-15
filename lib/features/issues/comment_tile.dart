import 'package:flutter/material.dart';
import 'package:paperplane/api/models/issue.dart';
import 'package:paperplane/core/error_presentation.dart';
import 'package:paperplane/features/inbox/inbox_format.dart';
import 'package:paperplane/features/issues/issue_thread.dart';
import 'package:paperplane/ui/ui.dart';

/// One confirmed comment. Agent comments sit on a gray panel with the agent's
/// avatar; comments from people are tinted and right-aligned, so the two read
/// apart at a glance (PRD S6 AC2).
class CommentTile extends StatelessWidget {
  /// Creates the tile.
  const new({
    required this.comment,
    required this.authorName,
    required this.mine,
    required this.now,
    required this.onOpenLink,
    super.key,
  });

  /// The comment.
  final IssueComment comment;

  /// Name shown above the text.
  final String authorName;

  /// True for a comment of the signed-in user.
  final bool mine;

  /// Reference time for the age.
  final DateTime now;

  /// Opens a link from the body in the browser.
  final void Function(Uri uri) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final isAgent = comment.authorKind == CommentAuthorKind.agent;
    final age = formatAge(comment.createdAt, now);
    final bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: isAgent ? pp.panel : pp.accentSoft,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Space.s2,
              runSpacing: Space.s1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (isAgent)
                  AppGhostAvatar(comment.authorAgentId ?? authorName)
                else
                  AppInitialsAvatar(authorName, size: 24),
                Text(
                  authorName,
                  style: pp.text.smallStrong.copyWith(color: pp.ink),
                ),
                if (isAgent) const AppPill('Agent'),
                if (age.isNotEmpty) Text(age, style: pp.text.micro),
              ],
            ),
            const SizedBox(height: Space.s2),
            AppMarkdown(comment.body, onOpenLink: onOpenLink),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: Align(
        alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width,
          ),
          child: Semantics(
            container: true,
            label:
                '${isAgent ? 'Agent ' : ''}$authorName'
                '${age.isEmpty ? '' : ', $age'}',
            child: bubble,
          ),
        ),
      ),
    );
  }
}

/// A reply the server has not confirmed: "Sending…", or "Not sent — Retry"
/// with the typed text kept (PRD S6 AC4).
class PendingTile extends StatelessWidget {
  /// Creates the tile.
  const new({
    required this.pending,
    required this.retryEnabled,
    required this.onRetry,
    required this.onEdit,
    super.key,
  });

  /// The unconfirmed reply.
  final PendingComment pending;

  /// False while another send is in flight (PRD G6).
  final bool retryEnabled;

  /// Resends the same body with the same id.
  final VoidCallback onRetry;

  /// Takes the text back into the composer (a new id when sent again).
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final failed = pending.failed;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: Align(
        alignment: Alignment.centerRight,
        child: Semantics(
          container: true,
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: failed ? pp.dangerSoft : pp.accentSoft,
              borderRadius: BorderRadius.circular(Radii.md),
              border: failed ? Border.all(color: pp.danger) : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(Space.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Plain text: the user's own words, shown as typed.
                  Text(pending.draft.trim(), style: pp.text.body),
                  const SizedBox(height: Space.s2),
                  if (!failed)
                    Text('Sending…', style: pp.text.micro)
                  else ...[
                    Text(
                      'Not sent — Retry',
                      style: pp.text.smallStrong.copyWith(color: pp.dangerInk),
                    ),
                    if (_detail(pending) case final detail?)
                      Text(detail, style: pp.text.small),
                    const SizedBox(height: Space.s2),
                    Wrap(
                      spacing: Space.s2,
                      children: [
                        AppButton(
                          label: 'Retry',
                          small: true,
                          onPressed: retryEnabled ? onRetry : null,
                        ),
                        AppButton(
                          label: 'Edit',
                          small: true,
                          style: AppButtonStyle.secondary,
                          onPressed: retryEnabled ? onEdit : null,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _detail(PendingComment pending) {
    final error = pending.error;
    if (error == null) return null;
    final p = presentationFor(error, forWrite: true);
    return switch (p.kind) {
      ErrorKind.offline => "Can't reach the server. Your text is kept.",
      ErrorKind.noAccess => p.message,
      ErrorKind.sessionExpired => 'Sign in again.',
      _ => p.detail ?? p.message,
    };
  }
}
