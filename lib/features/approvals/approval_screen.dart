import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/models/approval.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/core/error_presentation.dart';
import 'package:paperplane/core/submit_controller.dart';
import 'package:paperplane/features/approvals/approval_payload.dart';
import 'package:paperplane/features/approvals/approval_providers.dart';
import 'package:paperplane/features/inbox/company_providers.dart';
import 'package:paperplane/features/inbox/inbox_controller.dart';
import 'package:paperplane/features/inbox/inbox_format.dart';
import 'package:paperplane/ui/ui.dart';

/// S4: one approval, its body, linked issue and the approve/reject bar.
///
/// [attention] is the Inbox row that opened the screen. It carries the
/// server's `inlineResolvable` gate and the fallback web page. Without it (a
/// direct link) the screen is read-only, because the server is the authority
/// on what may be decided inline.
class ApprovalScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const new({required this.approvalId, this.attention, super.key});

  /// Approval to load.
  final String approvalId;

  /// The attention row that opened this screen, when there is one.
  final AttentionItem? attention;

  @override
  ConsumerState<ApprovalScreen> createState() => _ApprovalScreenState();
}

enum _Decision { approve, reject }

class _ApprovalScreenState extends ConsumerState<ApprovalScreen> {
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();
  final _scroll = ScrollController();
  bool _noteVisible = false;
  bool _rejectStep = false;
  _Decision? _sending;

  @override
  void dispose() {
    _comment.dispose();
    _commentFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _inline => widget.attention?.inlineResolvable ?? false;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final detail = ref.watch(approvalDetailProvider(widget.approvalId));
    final decision = ref.watch(approvalDecisionProvider(widget.approvalId));
    final session = ref.watch(sessionControllerProvider);
    final signedIn = session is SignedIn ? session : null;
    final approval = detail.value?.approval;
    final canDecide = approval != null && approval.isPending && _inline;
    final showBar = canDecide && decision is! SubmitAlreadyHandled<Approval>;
    final banner = _decisionBanner(decision, signedIn?.baseUrl.host);

    return Scaffold(
      backgroundColor: pp.bg,
      appBar: AppNavBar(title: 'Approval', onBack: _back),
      body: Column(
        children: [
          Expanded(
            child: AppColumn(
              child: AsyncStateView<ApprovalDetail>(
                value: detail,
                host: signedIn?.baseUrl.host,
                skeletonRows: 4,
                onRetry: () =>
                    ref.invalidate(approvalDetailProvider(widget.approvalId)),
                onBack: _back,
                builder: (context, data) => _body(data),
              ),
            ),
          ),
          if (banner != null)
            AppColumn(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.s4,
                  0,
                  Space.s4,
                  Space.s3,
                ),
                child: banner,
              ),
            ),
          if (showBar) _actionBar(decision),
        ],
      ),
    );
  }

  Widget _body(ApprovalDetail data) {
    final pp = context.pp;
    final approval = data.approval;
    final now = ref.read(clockProvider)();
    final requester = _requester(data);
    final age = formatAge(approval.createdAt, now);
    final title = _titleFor(approval);
    final summary = _summaryFor(approval);
    final baseUrl = switch (ref.watch(sessionControllerProvider)) {
      SignedIn(:final baseUrl) => baseUrl,
      _ => null,
    };
    final fallbackUrl = baseUrl == null
        ? null
        : webUrlFor(baseUrl, widget.attention?.subject.href);
    final needsFallback = !_inline || !approval.hasKnownBody;
    final currentUserId = approval.isPending
        ? null
        : ref.watch(sessionInfoProvider).value?.userId;

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s5,
      ),
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.s2,
          runSpacing: Space.s1,
          children: [
            Text('Requested by $requester', style: pp.text.small),
            if (age.isNotEmpty) Text('· $age', style: pp.text.small),
            AppPill(approval.status.label, tone: _tone(approval.status)),
          ],
        ),
        const SizedBox(height: Space.s3),
        Text(title, style: pp.text.h3),
        if (!approval.isPending) ...[
          const SizedBox(height: Space.s3),
          _decidedBlock(approval, currentUserId),
        ],
        const SizedBox(height: Space.s4),
        if (approval.isPending && !_inline)
          Text(
            'This request can only be decided in Paperclip.',
            style: pp.text.body.copyWith(color: pp.ink2),
          ),
        if (needsFallback) ...[
          if (summary != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.s3),
              child: Text(
                summary,
                style: pp.text.body.copyWith(color: pp.ink2),
              ),
            )
          else if (!approval.hasKnownBody)
            Text(
              'Some details of this request are only in Paperclip.',
              style: pp.text.body.copyWith(color: pp.ink2),
            ),
        ] else
          ApprovalPayloadView(approval: approval, onOpenLink: _openLink),
        if (data.linkedIssues.isNotEmpty) ...[
          const SizedBox(height: Space.s5),
          _linkedIssues(data.linkedIssues),
        ],
        if (needsFallback) ...[
          const SizedBox(height: Space.s4),
          if (fallbackUrl != null)
            AppButton(
              label: 'Open in Paperclip',
              style: AppButtonStyle.secondary,
              block: true,
              onPressed: () => _openLink(fallbackUrl),
            ),
        ],
        if (approval.isPending && _inline) ...[
          const SizedBox(height: Space.s4),
          _noteSection(),
        ],
      ],
    );
  }

  Widget _decidedBlock(Approval approval, String? currentUserId) {
    final pp = context.pp;
    final by = approval.decidedByUserId == null
        ? 'another board user'
        : approval.decidedByUserId == currentUserId
        ? 'you'
        : 'another board user';
    final when = approval.decidedAt == null
        ? ''
        : ' on ${_formatWhen(approval.decidedAt!)}';
    final note = approval.decisionNote;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pp.panel,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${approval.status.label} by $by$when',
              style: pp.text.smallStrong,
            ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: Space.s1),
              Text(note, style: pp.text.small),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linkedIssues(List<LinkedIssue> issues) {
    final pp = context.pp;
    final company = ref.watch(activeCompanyProvider);
    final baseUrl = switch (ref.watch(sessionControllerProvider)) {
      SignedIn(:final baseUrl) => baseUrl,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          issues.length > 1 ? 'LINKED ISSUES' : 'LINKED ISSUE',
          style: pp.text.sectionTitle,
        ),
        const SizedBox(height: Space.s2),
        AppCardList(
          children: [
            for (final issue in issues)
              AppListRow(
                title: issue.title,
                meta: Text(issue.identifier),
                chevron: true,
                semanticLabel:
                    'Linked issue ${issue.identifier}, ${issue.title}. '
                    'Opens in your browser',
                onTap: _issueOpener(company, baseUrl, issue),
              ),
          ],
        ),
      ],
    );
  }

  VoidCallback? _issueOpener(
    Company? company,
    Uri? baseUrl,
    LinkedIssue issue,
  ) {
    final prefix = company?.issuePrefix;
    if (baseUrl == null ||
        prefix == null ||
        prefix.isEmpty ||
        issue.identifier.isEmpty) {
      return null;
    }
    final url = webUrlFor(baseUrl, '/$prefix/issues/${issue.identifier}');
    return url == null ? null : () => _openLink(url);
  }

  Widget _noteSection() {
    final pp = context.pp;
    if (_rejectStep) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Reject this request? This can't be undone.",
            style: pp.text.body.copyWith(color: pp.dangerInk),
          ),
          const SizedBox(height: Space.s3),
          if (_noteVisible)
            AppTextField(
              label: 'Rejection note (optional)',
              controller: _comment,
              focusNode: _commentFocus,
              maxLines: 3,
              enabled: !_isSending,
              help: 'Only you and the requester see this.',
            ),
        ],
      );
    }
    if (_noteVisible) {
      return AppTextField(
        label: 'Comment (optional)',
        controller: _comment,
        focusNode: _commentFocus,
        maxLines: 3,
        enabled: !_isSending,
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AppButton(
        label: 'Add a comment (optional)',
        style: AppButtonStyle.ghost,
        small: true,
        onPressed: _isSending ? null : _showNote,
      ),
    );
  }

  Widget _actionBar(SubmitState<Approval> decision) {
    final busy = decision.isSubmitting;
    if (_rejectStep) {
      return AppActionBar(
        children: [
          AppButton(
            label: 'Cancel',
            style: AppButtonStyle.secondary,
            onPressed: busy ? null : _cancelReject,
          ),
          AppButton(
            label: 'Send rejection',
            style: AppButtonStyle.danger,
            loading: busy && _sending == _Decision.reject,
            loadingLabel: 'Sending rejection',
            onPressed: busy ? null : () => _decide(approve: false),
          ),
        ],
      );
    }
    return AppActionBar(
      children: [
        AppButton(
          label: 'Reject',
          style: AppButtonStyle.secondary,
          onPressed: busy ? null : _startReject,
        ),
        AppButton(
          label: 'Approve',
          loading: busy && _sending == _Decision.approve,
          loadingLabel: 'Approving',
          onPressed: busy ? null : () => _decide(approve: true),
        ),
      ],
    );
  }

  Widget? _decisionBanner(SubmitState<Approval> decision, String? host) {
    if (decision is SubmitAlreadyHandled<Approval>) {
      return const AppBanner(
        kind: AppBannerKind.info,
        title: 'Already handled',
        message: 'Someone else got there first. Showing the current state.',
      );
    }
    if (decision is! SubmitFailure<Approval>) return null;
    final p = presentationFor(decision.error, host: host, forWrite: true);
    return AppBanner(
      kind: p.kind == ErrorKind.offline
          ? AppBannerKind.offline
          : AppBannerKind.error,
      title: p.title,
      message: [p.message, ?p.detail].join(' '),
      actionLabel: p.retryable ? 'Retry' : null,
      onAction: p.retryable ? () => _decide(approve: !_rejectStep) : null,
    );
  }

  bool get _isSending => _sending != null;

  void _startReject() {
    setState(() {
      _rejectStep = true;
      _noteVisible = true;
    });
    _revealNote();
  }

  void _cancelReject() {
    setState(() {
      _rejectStep = false;
      _sending = null;
    });
    _comment.clear();
    _commentFocus.unfocus();
    _revealNote();
  }

  void _showNote() {
    setState(() => _noteVisible = true);
    _revealNote();
  }

  /// Brings the note field and the bar into view after they expand.
  void _revealNote() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: Motion.of(context, Motion.med),
          curve: Curves.easeOut,
        );
      }
      _commentFocus.requestFocus();
    });
  }

  Future<void> _decide({required bool approve}) async {
    final controller = ref.read(
      approvalDecisionProvider(widget.approvalId).notifier,
    );
    final repository = ref.read(approvalRepositoryProvider);
    final note = _comment.text;
    setState(() {
      _sending = approve ? _Decision.approve : _Decision.reject;
    });
    final ok = await controller.submit(
      () => approve
          ? repository.approve(widget.approvalId, decisionNote: note)
          : repository.reject(widget.approvalId, decisionNote: note),
      onAlreadyHandled: (_) async {
        ref.invalidate(approvalDetailProvider(widget.approvalId));
        await _refreshInbox();
      },
    );
    if (!mounted) return;
    setState(() => _sending = null);
    if (!ok) return;
    final result = ref.read(approvalDecisionProvider(widget.approvalId));
    if (result is SubmitSuccess<Approval>) {
      _removeFromInbox();
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  void _removeFromInbox() {
    final item = widget.attention;
    final company = ref.read(activeCompanyProvider);
    if (item == null || company == null) return;
    ref.read(inboxProvider(company.id).notifier).removeItem(item.id);
  }

  Future<void> _refreshInbox() async {
    final company = ref.read(activeCompanyProvider);
    if (company == null) return;
    await ref.read(inboxProvider(company.id).notifier).refresh(silent: true);
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

  String _titleFor(Approval approval) {
    final fromRow = widget.attention?.title;
    if (fromRow != null && fromRow.isNotEmpty) return fromRow;
    return approval.title;
  }

  String? _summaryFor(Approval approval) {
    final fromRow = widget.attention?.summary;
    if (fromRow != null && fromRow.isNotEmpty) return fromRow;
    return approval.summary;
  }

  String _requester(ApprovalDetail data) {
    final fromRow = widget.attention?.originAgentName;
    if (fromRow != null && fromRow.isNotEmpty) return fromRow;
    if (data.requesterName != null && data.requesterName!.isNotEmpty) {
      return data.requesterName!;
    }
    if (data.approval.requestedByAgentId != null) return 'an agent';
    if (data.approval.requestedByUserId != null) return 'a board user';
    return 'someone';
  }

  static AppPillTone _tone(ApprovalStatus status) => switch (status) {
    ApprovalStatus.approved => AppPillTone.blue,
    ApprovalStatus.rejected => AppPillTone.bad,
    ApprovalStatus.revisionRequested => AppPillTone.warn,
    ApprovalStatus.pending => AppPillTone.warn,
    ApprovalStatus.cancelled => AppPillTone.neutral,
    ApprovalStatus.unknown => AppPillTone.neutral,
  };

  static String _formatWhen(DateTime time) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = time.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, '
        '${local.hour}:$minute';
  }
}
