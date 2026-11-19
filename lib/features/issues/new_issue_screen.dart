import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/agent.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/api/models/issue.dart';
import 'package:paperplane/api/models/project.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/app/routes.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/core/error_presentation.dart';
import 'package:paperplane/core/submit_controller.dart';
import 'package:paperplane/features/inbox/company_providers.dart';
import 'package:paperplane/features/inbox/inbox_controller.dart';
import 'package:paperplane/features/issues/issue_thread.dart';
import 'package:paperplane/ui/ui.dart';

/// Longest title the form sends (PRD S7 AC2).
const int kNewIssueTitleLimit = 200;

/// The create request of S7. One write at a time, one tap one issue (G6).
final NotifierProvider<SubmitController<Issue>, SubmitState<Issue>>
newIssueSubmitProvider =
    NotifierProvider.autoDispose<SubmitController<Issue>, SubmitState<Issue>>(
      SubmitController.new,
    );

/// S7: create an issue with a title, an optional description, an assignee and
/// an optional project.
///
/// The title is focused on open. The assignee starts as the company's CEO, or
/// "Unassigned" when there is none. The project list loads only when asked for
/// and a failure leaves the form usable (S7 AC1-AC3).
class NewIssueScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  ConsumerState<NewIssueScreen> createState() => _NewIssueScreenState();
}

class _NewIssueScreenState extends ConsumerState<NewIssueScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _titleFocus = FocusNode();
  final _descriptionFocus = FocusNode();

  Agent? _assignee;
  bool _assigneeChosen = false;

  Project? _project;
  List<Project>? _projects;
  bool _loadingProjects = false;

  /// True once the user chose to leave; stops the discard prompt on our own
  /// pop and on the success navigation.
  bool _allowPop = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  bool get _titleTooLong => _title.text.trim().length > kNewIssueTitleLimit;

  bool get _dirty =>
      _title.text.trim().isNotEmpty || _description.text.trim().isNotEmpty;

  String? get _titleError => _titleTooLong
      ? 'Title must be $kNewIssueTitleLimit characters or fewer.'
      : null;

  void _changed() {
    // A new edit is a new attempt: clear the last failure.
    ref.read(newIssueSubmitProvider.notifier).reset();
    setState(() {});
  }

  Future<void> _pickAssignee(String companyId, List<Agent> agents) async {
    final choice = await showPickerSheet<Agent>(
      context: context,
      title: 'Assignee',
      options: [
        for (final agent in agents)
          if (agent.isActive)
            PickerOption(
              value: agent,
              label: agent.name,
              subtitle: agent.title ?? (agent.role.isEmpty ? null : agent.role),
            ),
      ],
      selected: _effectiveAssignee(agents),
      noneLabel: 'Unassigned',
      emptyText: 'No agents to assign.',
    );
    if (choice == null || !mounted) return;
    setState(() {
      _assigneeChosen = true;
      _assignee = choice.value;
    });
  }

  Agent? _effectiveAssignee(List<Agent> agents) =>
      _assigneeChosen ? _assignee : Agent.ceoOf(agents);

  Future<void> _pickProject(Company company) async {
    var projects = _projects;
    if (projects == null) {
      setState(() => _loadingProjects = true);
      try {
        projects = await ref
            .read(projectRepositoryProvider)
            .listProjects(company.id);
        if (!mounted) return;
        setState(() {
          _projects = projects;
          _loadingProjects = false;
        });
      } on ApiError {
        if (!mounted) return;
        setState(() => _loadingProjects = false);
        showAppToast(
          context,
          kind: AppToastKind.error,
          message: "Couldn't load projects. Try again.",
          actionLabel: 'Retry',
          onAction: () => unawaited(_pickProject(company)),
        );
        return;
      }
    }
    final choice = await showPickerSheet<Project>(
      context: context,
      title: 'Project',
      options: [
        for (final project in projects)
          PickerOption(value: project, label: project.name),
      ],
      selected: _project,
      noneLabel: 'No project',
      emptyText: 'No projects.',
    );
    if (choice == null || !mounted) return;
    setState(() => _project = choice.value);
  }

  Future<void> _create(Company company, List<Agent> agents) async {
    final controller = ref.read(newIssueSubmitProvider.notifier);
    await controller.submit(() {
      final description = _description.text.trim();
      return ref
          .read(issueRepositoryProvider)
          .createIssue(
            companyId: company.id,
            title: _title.text.trim(),
            description: description.isEmpty ? null : description,
            assigneeAgentId: _effectiveAssignee(agents)?.id,
            projectId: _project?.id,
          );
    });
    if (!mounted) return;
    if (ref.read(newIssueSubmitProvider) case SubmitSuccess<Issue>(
      :final value,
    )) {
      _created(company, value);
    }
  }

  void _created(Company company, Issue issue) {
    unawaited(ref.read(inboxProvider(company.id).notifier).refresh());
    _allowPop = true;
    if (issue.id.isEmpty) {
      // S6 is built, but an answer without an id cannot open it. The PRD's
      // fallback is S2 with a confirmation.
      final overlay = Overlay.of(context, rootOverlay: true);
      showAppToast(context, message: 'Created', overlay: overlay);
      Navigator.of(context).pop();
      return;
    }
    context.pushReplacement(AppRoutes.issue(issue.id));
  }

  Future<void> _back() async {
    if (ref.read(newIssueSubmitProvider).isSubmitting) return;
    if (_dirty) {
      final discard = await _confirmDiscard();
      if (!discard || !mounted) return;
    }
    _leaveNow();
  }

  void _leaveNow() {
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showAppSheet<bool>(
      context: context,
      builder: (sheetContext) {
        final pp = sheetContext.pp;
        return AppSheet(
          title: 'Discard this draft?',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The title and description you typed will be lost.',
                style: pp.text.small,
              ),
              const SizedBox(height: Space.s4),
              AppButton(
                label: 'Discard',
                style: AppButtonStyle.danger,
                block: true,
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
              const SizedBox(height: Space.s2),
              AppButton(
                label: 'Keep editing',
                style: AppButtonStyle.secondary,
                block: true,
                onPressed: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        );
      },
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final company = ref.watch(activeCompanyProvider);
    final submit = ref.watch(newIssueSubmitProvider);
    final submitting = submit.isSubmitting;
    final session = ref.watch(sessionControllerProvider);
    final host = session is SignedIn ? session.baseUrl.host : null;

    final agentsAsync = company == null
        ? null
        : ref.watch(threadAgentsProvider(company.id));
    final agents = agentsAsync?.value ?? const <Agent>[];
    final effectiveAssignee = _effectiveAssignee(agents);
    final assigneeValue = (agentsAsync?.isLoading ?? false) && !_assigneeChosen
        ? 'Loading…'
        : effectiveAssignee?.name ?? 'Unassigned';

    final canChooseAssignee =
        company != null && !submitting && !(agentsAsync?.isLoading ?? false);
    final canCreate =
        company != null &&
        !submitting &&
        _title.text.trim().isNotEmpty &&
        !_titleTooLong;

    return PopScope(
      canPop: !submitting && (_allowPop || !_dirty),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || submitting) return;
        final discard = await _confirmDiscard();
        if (discard) _leaveNow();
      },
      child: Scaffold(
        backgroundColor: pp.bg,
        appBar: AppNavBar(title: 'New issue', onBack: () => unawaited(_back())),
        body: company == null
            ? const AppColumn(
                child: Padding(
                  padding: EdgeInsets.all(Space.s5),
                  child: AppEmptyState(
                    title: 'No company',
                    message: 'Open the Inbox and choose a company first.',
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: AppColumn(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          Space.s4,
                          Space.s3,
                          Space.s4,
                          Space.s4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppTextField(
                              label: 'Title',
                              controller: _title,
                              focusNode: _titleFocus,
                              autofocus: true,
                              required: true,
                              enabled: !submitting,
                              help: 'Up to $kNewIssueTitleLimit characters.',
                              errorText: _titleError,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => _changed(),
                              onSubmitted: (_) =>
                                  _descriptionFocus.requestFocus(),
                            ),
                            const SizedBox(height: Space.s4),
                            AppTextField(
                              label: 'Description',
                              controller: _description,
                              focusNode: _descriptionFocus,
                              enabled: !submitting,
                              maxLines: 6,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              help: 'Optional. Markdown is supported.',
                              onChanged: (_) => _changed(),
                            ),
                            const SizedBox(height: Space.s4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: PickerChip(
                                label: 'Assignee',
                                value: assigneeValue,
                                icon: AppIconName.agents,
                                onTap: canChooseAssignee
                                    ? () => unawaited(
                                        _pickAssignee(company.id, agents),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: Space.s3),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: PickerChip(
                                label: 'Project',
                                value: _project?.name ?? 'None',
                                icon: AppIconName.folder,
                                onTap: submitting || _loadingProjects
                                    ? null
                                    : () => unawaited(_pickProject(company)),
                              ),
                            ),
                            if (submit case SubmitFailure<Issue>(
                              :final error,
                            )) ...[
                              const SizedBox(height: Space.s4),
                              _errorBanner(
                                error,
                                host: host,
                                onRetry: () =>
                                    unawaited(_create(company, agents)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  AppActionBar(
                    children: [
                      AppButton(
                        label: 'Create issue',
                        loadingLabel: 'Creating issue',
                        block: true,
                        loading: submitting,
                        onPressed: canCreate
                            ? () => unawaited(_create(company, agents))
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _errorBanner(
    ApiError error, {
    required String? host,
    required VoidCallback onRetry,
  }) {
    final p = presentationFor(error, host: host, forWrite: true);
    return AppBanner(
      kind: p.kind == ErrorKind.offline
          ? AppBannerKind.offline
          : AppBannerKind.error,
      title: p.title,
      message: [p.message, ?p.detail].join(' '),
      actionLabel: p.retryable ? 'Retry' : null,
      onAction: p.retryable ? onRetry : null,
    );
  }
}
