import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/agent.dart';
import 'package:paperplane/api/models/issue.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/core/error_presentation.dart';
import 'package:paperplane/features/issues/comment_tile.dart';
import 'package:paperplane/features/issues/issue_thread.dart';
import 'package:paperplane/features/issues/mentions.dart';
import 'package:paperplane/ui/ui.dart';

/// Id of the signed-in user, to label their own comments "You". Null when it
/// cannot be read; the thread still works.
final FutureProvider<String?> threadUserIdProvider =
    FutureProvider.autoDispose<String?>((ref) async {
      try {
        return (await ref.watch(sessionRepositoryProvider).me()).userId;
      } on Object {
        return null;
      }
    });

/// S6: one issue, its thread and the reply bar.
class IssueScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [issueId] (an id or an identifier like `ABC-12`).
  const new({required this.issueId, super.key});

  /// What the route carried.
  final String issueId;

  @override
  ConsumerState<IssueScreen> createState() => _IssueScreenState();
}

class _IssueScreenState extends ConsumerState<IssueScreen> {
  final _scroll = ScrollController();
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();

  /// Agents picked from the sheet for the text now in the composer.
  final Map<String, String> _mentions = {};

  /// Scroll state saved just before "Load earlier", to keep the view still
  /// when older comments are added above it.
  ({double pixels, double max})? _beforeEarlier;

  @override
  void initState() {
    super.initState();
    _reply.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  bool get _pinnedToBottom {
    if (!_scroll.hasClients) return true;
    final p = _scroll.position;
    return p.maxScrollExtent - p.pixels < 120;
  }

  /// Scrolls to the newest comment after the next frame.
  ///
  /// The list builds lazily, so its length is an estimate until the last
  /// comment has been laid out. After a jump the end can move; look again for
  /// a few frames until it stays put.
  void _jumpToBottom({bool animate = false, int attempts = 6}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (animate && !MediaQuery.disableAnimationsOf(context)) {
        _scroll.animateTo(
          max,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
        return;
      }
      _scroll.jumpTo(max);
      if (attempts > 1) _settleAtBottom(attempts - 1);
    });
  }

  void _settleAtBottom(int attempts) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent - 0.5) return;
      _scroll.jumpTo(position.maxScrollExtent);
      if (attempts > 1) _settleAtBottom(attempts - 1);
    });
  }

  void _onThreadChanged(IssueThreadState? prev, IssueThreadState next) {
    if (prev == null) return;
    // First time the thread is on screen: start at the latest comment.
    if (prev.issue == null && next.issue != null) {
      _jumpToBottom();
      return;
    }
    // Older comments were added above: keep what the user is reading still.
    final saved = _beforeEarlier;
    if (saved != null &&
        prev.loadingEarlier &&
        !next.loadingEarlier &&
        next.comments.length != prev.comments.length) {
      _beforeEarlier = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final grown = _scroll.position.maxScrollExtent - saved.max;
        _scroll.jumpTo(saved.pixels + (grown > 0 ? grown : 0));
      });
      return;
    }
    if (prev.loadingEarlier && !next.loadingEarlier) _beforeEarlier = null;
    // A reply was added at the bottom: show it. New comments from a refresh
    // keep the view at the bottom only if the user was already there.
    if (next.pending.length > prev.pending.length) {
      _jumpToBottom(animate: true);
    } else if (_lastId(next) != _lastId(prev) && _pinnedToBottom) {
      _jumpToBottom();
    }
  }

  static String? _lastId(IssueThreadState s) =>
      s.comments.isEmpty ? null : s.comments.last.id;

  Future<void> _loadEarlier() async {
    if (_scroll.hasClients) {
      _beforeEarlier = (
        pixels: _scroll.position.pixels,
        max: _scroll.position.maxScrollExtent,
      );
    }
    await ref.read(issueThreadProvider(widget.issueId).notifier).loadEarlier();
  }

  Future<void> _pickAgent(List<Agent> agents) async {
    final mentionable = [
      for (final a in agents)
        if (a.isActive && a.name.isNotEmpty) a,
    ];
    final choice = await showPickerSheet<Agent>(
      context: context,
      title: 'Mention an agent',
      options: [
        for (final a in mentionable)
          PickerOption(
            value: a,
            label: a.name,
            subtitle: a.title ?? (a.role.isEmpty ? null : a.role),
          ),
      ],
      emptyText: 'No agents to mention.',
    );
    final agent = choice?.value;
    if (agent == null || !mounted) return;
    final next = insertMention(_reply.value, agent.name);
    _mentions[agent.name] = agent.id;
    _reply.value = next;
    _replyFocus.requestFocus();
  }

  void _send() {
    final controller = ref.read(issueThreadProvider(widget.issueId).notifier);
    final result = controller.send(
      _reply.text,
      mentions: Map<String, String>.of(_mentions),
    );
    if (result.started) {
      // The text now lives in the pending reply; "Edit" brings it back.
      _reply.clear();
      _mentions.clear();
      unawaited(result.done);
    }
  }

  Future<void> _edit(PendingComment pending) async {
    final controller = ref.read(issueThreadProvider(widget.issueId).notifier);
    final result = await controller.edit(pending.id);
    if (!mounted) return;
    if (result.outcome == EditOutcome.delivered) {
      showAppToast(
        context,
        message: 'That reply was already sent. It is in the thread.',
      );
      return;
    }
    var reply = result.reply;
    if (result.outcome == EditOutcome.unresolved && reply != null) {
      final proceed = await _confirmUncertainEdit();
      if (!mounted || !proceed) return;
      reply = controller.discard(reply.id);
    }
    if (reply == null) return;
    _fillComposer(reply);
  }

  void _fillComposer(PendingComment reply) {
    _reply.value = TextEditingValue(
      text: reply.draft,
      selection: TextSelection.collapsed(offset: reply.draft.length),
    );
    _mentions
      ..clear()
      ..addAll(reply.mentions);
    _replyFocus.requestFocus();
  }

  /// Warns that an uncertain reply may already be on the server when the
  /// reconciliation read failed. True means the user chose to edit anyway.
  Future<bool> _confirmUncertainEdit() async {
    final choice = await showAppSheet<bool>(
      context: context,
      builder: (sheetContext) {
        final pp = sheetContext.pp;
        return AppSheet(
          title: 'Check the thread first',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The server did not answer this reply, so it may already be in '
                'the thread. Editing and sending again can post it twice.',
                style: pp.text.small,
              ),
              const SizedBox(height: Space.s4),
              AppButton(
                label: 'Edit anyway',
                style: AppButtonStyle.secondary,
                block: true,
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
              const SizedBox(height: Space.s2),
              AppButton(
                label: 'Cancel',
                block: true,
                onPressed: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        );
      },
    );
    return choice ?? false;
  }

  Future<void> _openLink(Uri uri) async {
    final session = ref.read(sessionControllerProvider);
    if (session is SignedIn && session.isDemo) {
      showAppToast(
        context,
        message: 'Demo mode. With a real server this opens in your browser.',
      );
      return;
    }
    final opened = await ref.read(urlOpenerProvider)(uri);
    if (!opened && mounted) {
      showAppToast(
        context,
        kind: AppToastKind.error,
        message: "Couldn't open the page in your browser.",
      );
    }
  }

  void _back() {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    ref.listen(issueThreadProvider(widget.issueId), _onThreadChanged);
    final thread = ref.watch(issueThreadProvider(widget.issueId));
    final session = ref.watch(sessionControllerProvider);
    final host = session is SignedIn ? session.baseUrl.host : null;
    final issue = thread.issue;
    final agents = issue == null || issue.companyId.isEmpty
        ? null
        : ref.watch(threadAgentsProvider(issue.companyId));
    final canSend =
        issue != null && _reply.text.trim().isNotEmpty && !thread.sendInFlight;
    void retry() => unawaited(
      ref.read(issueThreadProvider(widget.issueId).notifier).refresh(),
    );

    return Scaffold(
      backgroundColor: pp.bg,
      appBar: AppNavBar(title: issue?.identifier ?? 'Issue', onBack: _back),
      body: Column(
        children: [
          Expanded(
            child: AppColumn(
              child: issue == null
                  ? AsyncStateView<IssueThreadState>(
                      value: thread.error == null
                          ? const AsyncLoading()
                          : AsyncError(thread.error!, StackTrace.empty),
                      host: host,
                      skeletonRows: 4,
                      onRetry: retry,
                      onBack: _back,
                      builder: (context, data) => const SizedBox.shrink(),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (thread.error case final error?)
                          _staleBanner(error, host, thread.lastUpdated, retry),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: ref
                                .read(
                                  issueThreadProvider(widget.issueId).notifier,
                                )
                                .refresh,
                            child: _thread(thread, agents?.value ?? const []),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (issue != null)
            AppComposer(
              controller: _reply,
              focusNode: _replyFocus,
              leading: _MentionButton(
                onPressed: () =>
                    unawaited(_pickAgent(agents?.value ?? const [])),
              ),
              onSend: canSend ? _send : null,
            ),
        ],
      ),
    );
  }

  Widget _staleBanner(
    ApiError error,
    String? host,
    DateTime? lastUpdated,
    VoidCallback onRetry,
  ) {
    final p = presentationFor(error, host: host);
    final stamp = lastUpdated == null
        ? null
        : 'Last updated ${formatClock(lastUpdated)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, 0),
      child: AppBanner(
        kind: p.kind == ErrorKind.offline
            ? AppBannerKind.offline
            : AppBannerKind.error,
        title: p.title,
        message: p.kind == ErrorKind.offline
            ? (stamp ?? p.message)
            : [p.message, ?stamp].join(' '),
        actionLabel: p.retryable ? 'Retry' : null,
        onAction: p.retryable ? onRetry : null,
      ),
    );
  }

  Widget _thread(IssueThreadState data, List<Agent> agents) {
    final pp = context.pp;
    final issue = data.issue!;
    final now = ref.read(clockProvider)();
    final names = {for (final a in agents) a.id: a.name};
    final me = ref.watch(threadUserIdProvider).value;
    final comments = data.visibleComments;

    // One column in a scroll view, not a lazy list: every loaded comment is
    // laid out, so the scroll extent is exact. That is what lets the view stay
    // still when "Load earlier" adds a page above it. Pages of 50 keep the
    // cost small.
    return SingleChildScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(issue, names),
          const SizedBox(height: Space.s4),
          _description(issue),
          const SizedBox(height: Space.s5),
          Text('COMMENTS', style: pp.text.sectionTitle),
          const SizedBox(height: Space.s2),
          if (data.hasEarlier) _loadEarlierButton(data),
          if (comments.isEmpty && data.pending.isEmpty && !data.hasEarlier)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s4),
              child: Text(
                'No comments yet.',
                style: pp.text.body.copyWith(color: pp.ink2),
              ),
            ),
          for (final comment in comments)
            CommentTile(
              key: ValueKey(comment.id),
              comment: comment,
              authorName: _authorName(comment, names, me),
              mine:
                  comment.authorKind == CommentAuthorKind.user &&
                  comment.authorUserId == me,
              now: now,
              onOpenLink: _openLink,
            ),
          for (final pending in data.pending)
            PendingTile(
              key: ValueKey('pending-${pending.id}'),
              pending: pending,
              retryEnabled: !data.sendInFlight,
              onRetry: () => unawaited(
                ref
                    .read(issueThreadProvider(widget.issueId).notifier)
                    .retry(pending.id),
              ),
              onEdit: () => unawaited(_edit(pending)),
            ),
          if (issue.status.isClosed)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: Text(
                'This issue is ${issue.status.label.toLowerCase()}. '
                'The server decides whether a reply is accepted.',
                style: pp.text.small,
              ),
            ),
        ],
      ),
    );
  }

  Widget _loadEarlierButton(IssueThreadState data) {
    final error = data.earlierError;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            const Padding(
              padding: EdgeInsets.only(bottom: Space.s2),
              child: AppErrorText("Couldn't load earlier comments."),
            ),
          AppButton(
            label: 'Load earlier',
            style: AppButtonStyle.secondary,
            block: true,
            loading: data.loadingEarlier,
            loadingLabel: 'Loading earlier comments',
            onPressed: data.loadingEarlier
                ? null
                : () => unawaited(_loadEarlier()),
          ),
        ],
      ),
    );
  }

  String _authorName(
    IssueComment comment,
    Map<String, String> names,
    String? me,
  ) => switch (comment.authorKind) {
    CommentAuthorKind.agent => names[comment.authorAgentId] ?? 'Agent',
    CommentAuthorKind.user =>
      comment.authorUserId != null && comment.authorUserId == me
          ? 'You'
          : 'Board user',
    CommentAuthorKind.other => 'System',
  };

  Widget _header(Issue issue, Map<String, String> names) {
    final pp = context.pp;
    final assignee = issue.assigneeAgentId != null
        ? (names[issue.assigneeAgentId] ?? 'Agent')
        : issue.assigneeUserId != null
        ? 'A person'
        : 'Unassigned';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(issue.title, style: pp.text.h3)),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppPill(issue.statusLabel, tone: _tone(issue.status)),
            AppPill('Assignee: $assignee', tone: AppPillTone.outline),
            if (issue.projectName != null)
              AppPill(
                'Project: ${issue.projectName}',
                tone: AppPillTone.outline,
              ),
          ],
        ),
      ],
    );
  }

  static AppPillTone _tone(IssueStatus status) => switch (status) {
    IssueStatus.blocked => AppPillTone.bad,
    IssueStatus.inReview => AppPillTone.warn,
    IssueStatus.inProgress => AppPillTone.blue,
    _ => AppPillTone.neutral,
  };

  Widget _description(Issue issue) {
    final pp = context.pp;
    final text = issue.description;
    if (text == null) {
      return Text(
        'No description.',
        style: pp.text.body.copyWith(color: pp.ink2),
      );
    }
    return AppMarkdown(text, onOpenLink: _openLink);
  }
}

class _MentionButton extends StatelessWidget {
  const new({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return Semantics(
      button: true,
      label: 'Mention an agent',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: Sizes.tap,
          height: Sizes.tap,
          child: Center(
            child: Text('@', style: pp.text.h.copyWith(color: pp.accent)),
          ),
        ),
      ),
    );
  }
}
