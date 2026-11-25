import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/json.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/interaction.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/core/error_presentation.dart';
import 'package:paperplane/core/submit_controller.dart';
import 'package:paperplane/data/interaction_repository.dart';
import 'package:paperplane/features/inbox/company_providers.dart';
import 'package:paperplane/features/inbox/inbox_controller.dart';
import 'package:paperplane/features/inbox/inbox_format.dart';
import 'package:paperplane/features/interactions/interaction_providers.dart';
import 'package:paperplane/ui/ui.dart';

/// S5 route host: opens the question/confirmation sheet over the Inbox.
///
/// The route exists so a row tap, a deep link and the browser stopgap all use
/// one place. The actual form is a modal sheet; closing it pops this route.
class InteractionScreen extends ConsumerStatefulWidget {
  /// Creates the host.
  const new({
    required this.issueId,
    required this.interactionId,
    this.attention,
    super.key,
  });

  /// Issue that owns the interaction.
  final String issueId;

  /// Interaction to show.
  final String interactionId;

  /// The Inbox row that opened this screen, when there is one.
  final AttentionItem? attention;

  @override
  ConsumerState<InteractionScreen> createState() => _InteractionScreenState();
}

class _InteractionScreenState extends ConsumerState<InteractionScreen> {
  final ValueNotifier<bool> _locked = ValueNotifier(false);
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _locked.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opened || !mounted) return;
    _opened = true;
    await showAppSheet<void>(
      context: context,
      locked: _locked,
      builder: (_) => _InteractionSheet(
        issueId: widget.issueId,
        interactionId: widget.interactionId,
        attention: widget.attention,
        locked: _locked,
      ),
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.transparent,
    body: SizedBox.expand(),
  );
}

class _InteractionSheet extends ConsumerStatefulWidget {
  const new({
    required this.issueId,
    required this.interactionId,
    required this.locked,
    this.attention,
  });

  final String issueId;
  final String interactionId;
  final AttentionItem? attention;
  final ValueNotifier<bool> locked;

  @override
  ConsumerState<_InteractionSheet> createState() => _InteractionSheetState();
}

class _InteractionSheetState extends ConsumerState<_InteractionSheet> {
  final _selected = <String, Set<String>>{};
  final _texts = <String, TextEditingController>{};
  final _reason = TextEditingController();
  final _checked = <String>{};
  bool _checkedReady = false;
  bool _rejecting = false;
  bool _dirty = false;
  Future<void> Function()? _retry;

  /// True when the last 409 left the re-read row still pending. A workspace
  /// that is still syncing answers that way, so "Already handled" would lie.
  bool _conflictStillPending = false;

  /// Server text for the last 409, shown while the row is still pending.
  String _conflictMessage = '';

  InteractionKey get _key => InteractionKey(
    issueId: widget.issueId,
    interactionId: widget.interactionId,
  );

  @override
  void dispose() {
    for (final controller in _texts.values) {
      controller.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(interactionProvider(_key));
    final write = ref.watch(interactionWriteProvider(_key));

    return AppSheet(
      title: _titleFor(detail.value),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_banner(write) case final banner?) ...[
            banner,
            const SizedBox(height: Space.s3),
          ],
          if (detail.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.s6),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (detail.hasError)
            _loadError(detail.error!)
          else if (detail.value == null)
            _gone()
          else
            _content(detail.value!, write),
        ],
      ),
    );
  }

  String _titleFor(Interaction? interaction) =>
      interaction?.kind.label ?? 'Question';

  Widget _loadError(Object error) {
    final host = switch (ref.watch(sessionControllerProvider)) {
      SignedIn(:final baseUrl) => baseUrl.host,
      _ => null,
    };
    final p = presentationFor(
      error is ApiError ? error : const Unexpected(),
      host: host,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppBanner(
          kind: AppBannerKind.error,
          title: p.title,
          message: p.message,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(interactionProvider(_key)),
        ),
        const SizedBox(height: Space.s4),
        AppButton(
          label: 'Close',
          style: AppButtonStyle.secondary,
          block: true,
          onPressed: _close,
        ),
      ],
    );
  }

  Widget _gone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This item is no longer waiting for you.',
          style: context.pp.text.body,
        ),
        const SizedBox(height: Space.s4),
        AppButton(
          label: 'Close',
          style: AppButtonStyle.secondary,
          block: true,
          onPressed: _close,
        ),
      ],
    );
  }

  Widget _content(Interaction interaction, SubmitState<Interaction> write) {
    final pp = context.pp;
    final inline = widget.attention?.inlineResolvable ?? true;
    if (!interaction.isPending) return _closed(interaction);
    final heading = interaction.heading;
    final supported = interaction.canResolveInline && inline;
    final readOnly =
        write is SubmitFailure<Interaction> && write.error is Forbidden;
    final unsupported = !supported;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(heading, style: pp.text.h3),
        if (interaction.summary case final summary?
            when summary.isNotEmpty && summary != heading) ...[
          const SizedBox(height: Space.s2),
          Text(summary, style: pp.text.body.copyWith(color: pp.ink2)),
        ],
        const SizedBox(height: Space.s4),
        if (unsupported)
          _unsupported(interaction)
        else
          switch (interaction.kind) {
            InteractionKind.askUserQuestions => _questions(
              interaction,
              write,
              readOnly: readOnly,
            ),
            InteractionKind.requestConfirmation => _confirmation(
              interaction,
              write,
              readOnly: readOnly,
            ),
            InteractionKind.suggestTasks => _suggestedTasks(
              interaction,
              write,
              readOnly: readOnly,
            ),
            InteractionKind.requestCheckboxConfirmation => _checklist(
              interaction,
              write,
              readOnly: readOnly,
            ),
            _ => _unsupported(interaction),
          },
        const SizedBox(height: Space.s5),
        if (!unsupported)
          AppButton(
            label: 'Close',
            style: AppButtonStyle.ghost,
            onPressed: write.isSubmitting ? null : _close,
          ),
      ],
    );
  }

  Widget _unsupported(Interaction interaction) {
    final pp = context.pp;
    final url = _webUrl();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (interaction.confirmation.detailsMarkdown case final details?
            when details.isNotEmpty)
          AppMarkdown(details, onOpenLink: _openLink),
        const SizedBox(height: Space.s3),
        Text(
          "This question type isn't supported in the app yet. Open it in "
          'Paperclip to answer.',
          style: pp.text.body.copyWith(color: pp.ink2),
        ),
        const SizedBox(height: Space.s4),
        if (url != null)
          AppButton(
            label: 'Open in Paperclip',
            style: AppButtonStyle.secondary,
            block: true,
            onPressed: () => _openLink(url),
          ),
        const SizedBox(height: Space.s2),
        AppButton(
          label: 'Close',
          style: AppButtonStyle.ghost,
          onPressed: _close,
        ),
      ],
    );
  }

  Widget _questions(
    Interaction interaction,
    SubmitState<Interaction> write, {
    required bool readOnly,
  }) {
    final pp = context.pp;
    final form = interaction.questionForm;
    final busy = write.isSubmitting || readOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (form.title case final title? when title.isNotEmpty) ...[
          Text(title, style: pp.text.smallStrong),
          const SizedBox(height: Space.s2),
        ],
        if (form.description case final description?
            when description.isNotEmpty) ...[
          AppMarkdown(description, onOpenLink: _openLink),
          const SizedBox(height: Space.s3),
        ],
        for (var i = 0; i < form.questions.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.s4),
          _question(form.questions[i], enabled: !busy),
        ],
        const SizedBox(height: Space.s5),
        if (!readOnly)
          AppButton(
            label: form.submitLabel ?? 'Send answer',
            block: true,
            loading: write.isSubmitting,
            loadingLabel: 'Sending answer',
            onPressed: busy || !_answersValid(form)
                ? null
                : () => _respond(form),
          ),
      ],
    );
  }

  Widget _question(InteractionQuestion question, {required bool enabled}) {
    final pp = context.pp;
    final selected = _selected.putIfAbsent(question.id, () => <String>{});
    final text = _textFor(question.id);
    final freeText = question.freeTextOption;
    final freeSelected = freeText != null && selected.contains(freeText.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: question.prompt,
            children: [
              if (question.required)
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: pp.danger),
                ),
            ],
          ),
          style: pp.text.body.copyWith(fontWeight: FontWeight.w600),
        ),
        if (question.helpText case final help? when help.isNotEmpty) ...[
          const SizedBox(height: Space.s1),
          Text(help, style: pp.text.small.copyWith(color: pp.ink3)),
        ],
        const SizedBox(height: Space.s2),
        if (question.isFreeTextOnly)
          _freeTextField(question, text, enabled: enabled)
        else
          AppCardList(
            children: [
              for (final option in question.options)
                _choiceTile(
                  option: option,
                  multi: question.multiSelect,
                  selected: selected.contains(option.id),
                  enabled: enabled,
                  onTap: () => _toggle(
                    question,
                    option,
                    selected,
                    multi: question.multiSelect,
                  ),
                ),
            ],
          ),
        if (freeText != null && !question.isFreeTextOnly) ...[
          if (freeSelected)
            Padding(
              padding: const EdgeInsets.only(top: Space.s3),
              child: _freeTextField(question, text, enabled: enabled),
            ),
        ],
      ],
    );
  }

  Widget _freeTextField(
    InteractionQuestion question,
    TextEditingController controller, {
    required bool enabled,
  }) {
    final maxLength = question.textRules.maxLength;
    final value = controller.text.trim();
    final tooShort =
        value.isNotEmpty &&
        question.textRules.minLength != null &&
        value.length < question.textRules.minLength!;
    return AppTextField(
      label: 'Your answer',
      controller: controller,
      enabled: enabled,
      maxLines: 4,
      help: maxLength == null ? null : 'Up to $maxLength characters.',
      errorText: tooShort
          ? 'Use at least ${question.textRules.minLength} characters.'
          : null,
      onChanged: (_) {
        setState(() => _dirty = true);
        _syncLocked();
      },
    );
  }

  Widget _choiceTile({
    required InteractionOption option,
    required bool multi,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final pp = context.pp;
    return Semantics(
      button: true,
      selected: selected,
      label: [option.label, ?option.description].join('. '),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.tapLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3,
              vertical: Space.s2,
            ),
            child: Row(
              children: [
                _ChoiceMark(selected: selected, multi: multi),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(option.label, style: pp.text.body),
                      if (option.description case final description?
                          when description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            description,
                            style: pp.text.small.copyWith(color: pp.ink3),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggle(
    InteractionQuestion question,
    InteractionOption option,
    Set<String> selected, {
    required bool multi,
  }) {
    setState(() {
      _dirty = true;
      if (multi) {
        if (!selected.add(option.id)) selected.remove(option.id);
      } else {
        selected
          ..clear()
          ..add(option.id);
      }
    });
    _syncLocked();
  }

  bool _answersValid(InteractionQuestionForm form) {
    for (final question in form.questions) {
      final selected = _selected[question.id] ?? const <String>{};
      final text = _textFor(question.id).text.trim();
      final freeText = question.freeTextOption;
      final freeSelected = freeText != null && selected.contains(freeText.id);
      final rules = question.textRules;
      if (freeSelected && text.isEmpty) return false;
      if (question.isFreeTextOnly) {
        if (question.required && text.isEmpty) return false;
        if (text.isEmpty) continue;
      } else if (question.required && selected.isEmpty) {
        return false;
      }
      if (text.isNotEmpty && rules.minLength != null) {
        if (text.length < rules.minLength!) return false;
      }
      if (rules.maxLength != null && text.length > rules.maxLength!) {
        return false;
      }
      if (text.length > _maxAnswerLength) return false;
    }
    return true;
  }

  List<QuestionAnswer> _answers(InteractionQuestionForm form) {
    final answers = <QuestionAnswer>[];
    for (final question in form.questions) {
      final selected = _selected[question.id] ?? const <String>{};
      final text = _textFor(question.id).text.trim();
      final freeText = question.freeTextOption;
      final freeSelected = freeText != null && selected.contains(freeText.id);
      final optionIds = [
        for (final id in selected)
          if (!(freeText != null && id == freeText.id)) id,
      ];
      if (question.isFreeTextOnly) {
        if (text.isEmpty) continue;
        answers.add(
          QuestionAnswer(
            questionId: question.id,
            optionIds: [freeText?.id ?? 'paperclip_text_answer'],
            otherText: text,
          ),
        );
        continue;
      }
      if (optionIds.isEmpty && !freeSelected) continue;
      answers.add(
        QuestionAnswer(
          questionId: question.id,
          optionIds: [...optionIds, if (freeSelected) freeText.id],
          otherText: freeSelected && text.isNotEmpty ? text : null,
        ),
      );
    }
    return answers;
  }

  Widget _confirmation(
    Interaction interaction,
    SubmitState<Interaction> write, {
    required bool readOnly,
  }) {
    final pp = context.pp;
    final confirmation = interaction.confirmation;
    final busy = write.isSubmitting || readOnly;
    final blocked = interaction.acceptBlocked;
    final reasonRequired = confirmation.rejectRequiresReason;
    final canReject = !reasonRequired || _reason.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (confirmation.prompt.isNotEmpty &&
            confirmation.prompt != interaction.heading) ...[
          Text(confirmation.prompt, style: pp.text.body),
          const SizedBox(height: Space.s3),
        ],
        if (confirmation.detailsMarkdown case final details?
            when details.isNotEmpty)
          AppMarkdown(details, onOpenLink: _openLink),
        if (confirmation.targetLabel case final label?
            when label.isNotEmpty) ...[
          const SizedBox(height: Space.s3),
          AppKeyValueCard(rows: [AppKeyValue('Document', label)]),
        ],
        if (_rejecting && !readOnly) ...[
          const SizedBox(height: Space.s4),
          AppTextField(
            label: confirmation.rejectReasonLabel ?? 'Reason',
            controller: _reason,
            enabled: !busy,
            maxLines: 3,
            required: reasonRequired,
            help: reasonRequired ? null : 'Optional.',
            onChanged: (_) {
              setState(() {
                _dirty = true;
              });
              _syncLocked();
            },
          ),
          const SizedBox(height: Space.s4),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  style: AppButtonStyle.secondary,
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          _rejecting = false;
                          _reason.clear();
                        }),
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: AppButton(
                  label: confirmation.rejectLabel ?? 'Reject',
                  style: AppButtonStyle.danger,
                  loading: busy,
                  loadingLabel: 'Rejecting',
                  onPressed: busy || !canReject
                      ? null
                      : () => _reject(interaction),
                ),
              ),
            ],
          ),
        ] else if (!readOnly)
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: confirmation.rejectLabel ?? 'Reject',
                  style: AppButtonStyle.secondary,
                  onPressed: busy
                      ? null
                      : () => _startReject(
                          interaction,
                          requiresReason: confirmation.rejectRequiresReason,
                          allowReason: confirmation.allowDeclineReason,
                        ),
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: AppButton(
                  label: confirmation.acceptLabel ?? 'Approve',
                  loading: busy,
                  loadingLabel: 'Sending',
                  onPressed: busy || blocked
                      ? null
                      : () => _accept(interaction, message: 'Confirmed'),
                ),
              ),
            ],
          ),
        const SizedBox(height: Space.s2),
        if (blocked)
          _blockedNotice()
        else
          Text(
            'This answer goes to the agent that asked.',
            style: pp.text.small.copyWith(color: pp.ink3),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Widget _blockedNotice() {
    final pp = context.pp;
    return Text(
      'Preparing approval. The workspace is still syncing; this will be '
      'ready shortly.',
      style: pp.text.small.copyWith(color: pp.ink3),
      textAlign: TextAlign.center,
    );
  }

  Widget _suggestedTasks(
    Interaction interaction,
    SubmitState<Interaction> write, {
    required bool readOnly,
  }) {
    final pp = context.pp;
    final suggested = interaction.suggestedTasks;
    final busy = write.isSubmitting || readOnly;
    final blocked = interaction.acceptBlocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          suggested.tasks.length == 1
              ? 'The agent will create this task.'
              : 'The agent will create these ${suggested.tasks.length} tasks.',
          style: pp.text.body.copyWith(color: pp.ink2),
        ),
        const SizedBox(height: Space.s3),
        AppCardList(
          children: [
            for (final task in suggested.tasks)
              Padding(
                padding: const EdgeInsets.all(Space.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(task.title, style: pp.text.body)),
                        if (task.priority case final priority?)
                          AppPill(priority),
                      ],
                    ),
                    if (task.description case final description?
                        when description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s1),
                        child: Text(
                          description,
                          style: pp.text.small.copyWith(color: pp.ink3),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        if (_rejecting && !readOnly) ...[
          const SizedBox(height: Space.s4),
          AppTextField(
            label: 'Reason (optional)',
            controller: _reason,
            enabled: !busy,
            maxLines: 3,
            onChanged: (_) {
              setState(() {
                _dirty = true;
              });
              _syncLocked();
            },
          ),
          const SizedBox(height: Space.s4),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  style: AppButtonStyle.secondary,
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          _rejecting = false;
                          _reason.clear();
                        }),
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: AppButton(
                  label: 'Reject tasks',
                  style: AppButtonStyle.danger,
                  loading: busy,
                  onPressed: busy ? null : () => _reject(interaction),
                ),
              ),
            ],
          ),
        ] else if (!readOnly)
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Reject',
                  style: AppButtonStyle.secondary,
                  onPressed: busy
                      ? null
                      : () => setState(() => _rejecting = true),
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: AppButton(
                  label: 'Create tasks',
                  loading: busy,
                  loadingLabel: 'Creating',
                  onPressed: busy || blocked
                      ? null
                      : () => _accept(
                          interaction,
                          selectedClientKeys: [
                            for (final task in suggested.tasks) task.clientKey,
                          ],
                          message: 'Tasks created',
                        ),
                ),
              ),
            ],
          ),
        const SizedBox(height: Space.s2),
        if (blocked)
          _blockedNotice()
        else
          Text(
            'The server creates all tasks in one batch.',
            style: pp.text.small.copyWith(color: pp.ink3),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Widget _checklist(
    Interaction interaction,
    SubmitState<Interaction> write, {
    required bool readOnly,
  }) {
    final pp = context.pp;
    final checklist = interaction.checklist;
    final busy = write.isSubmitting || readOnly;
    final blocked = interaction.acceptBlocked;
    if (!_checkedReady) {
      _checked
        ..clear()
        ..addAll(checklist.defaultSelected);
      _checkedReady = true;
    }
    final valid = checklist.isValid(_checked);
    final reasonRequired = checklist.rejectRequiresReason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(checklist.prompt, style: pp.text.body),
        if (checklist.detailsMarkdown case final details?
            when details.isNotEmpty) ...[
          const SizedBox(height: Space.s3),
          AppMarkdown(details, onOpenLink: _openLink),
        ],
        const SizedBox(height: Space.s3),
        AppCardList(
          children: [
            for (final option in checklist.options)
              _choiceTile(
                option: option,
                multi: true,
                selected: _checked.contains(option.id),
                enabled: !busy,
                onTap: () {
                  setState(() {
                    _dirty = true;
                    if (!_checked.add(option.id)) _checked.remove(option.id);
                  });
                  _syncLocked();
                },
              ),
          ],
        ),
        const SizedBox(height: Space.s2),
        Text(
          _selectionHint(checklist),
          style: pp.text.small.copyWith(color: pp.ink3),
        ),
        if (_rejecting && !readOnly) ...[
          const SizedBox(height: Space.s4),
          AppTextField(
            label: checklist.rejectReasonLabel ?? 'Reason',
            controller: _reason,
            enabled: !busy,
            maxLines: 3,
            required: reasonRequired,
            help: reasonRequired ? null : 'Optional.',
            onChanged: (_) {
              setState(() {
                _dirty = true;
              });
              _syncLocked();
            },
          ),
          const SizedBox(height: Space.s4),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  style: AppButtonStyle.secondary,
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          _rejecting = false;
                          _reason.clear();
                        }),
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: AppButton(
                  label: checklist.rejectLabel ?? 'Reject',
                  style: AppButtonStyle.danger,
                  loading: busy,
                  onPressed:
                      busy || (reasonRequired && _reason.text.trim().isEmpty)
                      ? null
                      : () => _reject(interaction),
                ),
              ),
            ],
          ),
        ] else if (!readOnly)
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: checklist.rejectLabel ?? 'Reject',
                  style: AppButtonStyle.secondary,
                  onPressed: busy
                      ? null
                      : () => _startReject(
                          interaction,
                          requiresReason: checklist.rejectRequiresReason,
                          allowReason: checklist.allowDeclineReason,
                        ),
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: AppButton(
                  label: checklist.acceptLabel ?? 'Confirm',
                  loading: busy,
                  loadingLabel: 'Sending',
                  onPressed: busy || blocked || !valid
                      ? null
                      : () => _accept(
                          interaction,
                          selectedOptionIds: [..._checked],
                          message: 'Confirmed',
                        ),
                ),
              ),
            ],
          ),
        if (blocked) ...[const SizedBox(height: Space.s2), _blockedNotice()],
      ],
    );
  }

  String _selectionHint(InteractionChecklist checklist) {
    final max = checklist.maxSelected;
    if (max == null) {
      return checklist.minSelected > 0
          ? 'Select at least ${checklist.minSelected}.'
          : 'Select any.';
    }
    if (checklist.minSelected == max) {
      return 'Select $max.';
    }
    return 'Select ${checklist.minSelected} to $max.';
  }

  Widget _closed(Interaction interaction) {
    final pp = context.pp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This item is ${interaction.finalStateLabel.toLowerCase()}.',
          style: pp.text.body,
        ),
        if (interaction.kind == InteractionKind.askUserQuestions) ...[
          const SizedBox(height: Space.s3),
          _answersView(interaction),
        ],
        if (_selectedOptionsView(interaction) case final selected?)
          if (selected.isNotEmpty) ...[
            const SizedBox(height: Space.s3),
            AppKeyValueCard(rows: [AppKeyValue('Options', selected)]),
          ],
        const SizedBox(height: Space.s4),
        AppButton(
          label: 'Close',
          style: AppButtonStyle.secondary,
          block: true,
          onPressed: _close,
        ),
      ],
    );
  }

  Widget _answersView(Interaction interaction) {
    final pp = context.pp;
    final form = interaction.questionForm;
    final answers = asAnswerMaps(interaction.result);
    if (answers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final answer in answers) ...[
          Text(
            _promptFor(form, readString(answer, 'questionId')),
            style: pp.text.smallStrong,
          ),
          const SizedBox(height: Space.s1),
          Text(
            _answerText(form, answer),
            style: pp.text.body.copyWith(color: pp.ink2),
          ),
          const SizedBox(height: Space.s3),
        ],
      ],
    );
  }

  String? _selectedOptionsView(Interaction interaction) {
    final ids = [
      for (final id in asStringList(interaction.result['selectedOptionIds']))
        id,
    ];
    if (ids.isEmpty) return null;
    final labels = <String>[];
    if (interaction.kind == InteractionKind.requestCheckboxConfirmation) {
      final byId = {
        for (final option in interaction.checklist.options) option.id: option,
      };
      for (final id in ids) {
        labels.add(byId[id]?.label ?? id);
      }
    }
    return labels.isEmpty ? ids.join(', ') : labels.join(', ');
  }

  String _promptFor(InteractionQuestionForm form, String? id) {
    for (final question in form.questions) {
      if (question.id == id) return question.prompt;
    }
    return 'Question';
  }

  String _answerText(
    InteractionQuestionForm form,
    Map<String, Object?> answer,
  ) {
    final id = readString(answer, 'questionId');
    InteractionQuestion? question;
    for (final row in form.questions) {
      if (row.id == id) question = row;
    }
    final labels = <String>[];
    final optionIds = asStringList(answer['optionIds']);
    if (question != null) {
      final byId = {for (final option in question.options) option.id: option};
      for (final optionId in optionIds) {
        final option = byId[optionId];
        if (option == null || option.freeText) continue;
        labels.add(option.label);
      }
    }
    final otherText = readNonEmpty(answer, 'otherText');
    if (otherText != null) labels.add(otherText);
    return labels.isEmpty ? 'No answer' : labels.join(', ');
  }

  Widget? _banner(SubmitState<Interaction> write) {
    if (write is SubmitAlreadyHandled<Interaction>) {
      if (_conflictStillPending) {
        return AppBanner(
          kind: AppBannerKind.error,
          title: 'Not ready yet',
          message: _conflictMessage.isEmpty
              ? 'The item is still waiting. Try again shortly.'
              : _conflictMessage,
        );
      }
      return const AppBanner(
        kind: AppBannerKind.info,
        title: 'Already handled',
        message: 'Someone else got there first. Showing the current state.',
      );
    }
    if (write is! SubmitFailure<Interaction>) return null;
    final host = switch (ref.watch(sessionControllerProvider)) {
      SignedIn(:final baseUrl) => baseUrl.host,
      _ => null,
    };
    final p = presentationFor(write.error, host: host, forWrite: true);
    final retry = _retry;
    return AppBanner(
      kind: p.kind == ErrorKind.offline
          ? AppBannerKind.offline
          : AppBannerKind.error,
      title: p.title,
      message: [p.message, ?p.detail].join(' '),
      actionLabel: p.retryable && retry != null ? 'Retry' : null,
      onAction: p.retryable && retry != null ? () => unawaited(retry()) : null,
    );
  }

  TextEditingController _textFor(String questionId) =>
      _texts.putIfAbsent(questionId, TextEditingController.new);

  void _startReject(
    Interaction interaction, {
    required bool requiresReason,
    required bool allowReason,
  }) {
    if (!requiresReason && !allowReason) {
      unawaited(_reject(interaction));
      return;
    }
    setState(() {
      _rejecting = true;
      _dirty = true;
    });
    _syncLocked();
  }

  Future<void> _respond(InteractionQuestionForm form) async {
    final interaction = ref.read(interactionProvider(_key)).value;
    if (interaction == null) return;
    await _run(
      () => ref
          .read(interactionRepositoryProvider)
          .respond(widget.issueId, widget.interactionId, _answers(form)),
      message: 'Answer sent',
    );
  }

  Future<void> _accept(
    Interaction interaction, {
    required String message,
    List<String> selectedClientKeys = const [],
    List<String> selectedOptionIds = const [],
  }) async {
    await _run(
      () => ref
          .read(interactionRepositoryProvider)
          .accept(
            widget.issueId,
            widget.interactionId,
            selectedClientKeys: selectedClientKeys,
            selectedOptionIds: selectedOptionIds,
          ),
      message: message,
    );
  }

  Future<void> _reject(Interaction interaction) async {
    final reason = _reason.text;
    await _run(
      () => ref
          .read(interactionRepositoryProvider)
          .reject(widget.issueId, widget.interactionId, reason: reason),
      message: 'Rejected',
    );
  }

  Future<void> _run(
    Future<Interaction> Function() action, {
    required String message,
  }) async {
    _retry = () => _run(action, message: message);
    final overlay = Overlay.of(context, rootOverlay: true);
    final controller = ref.read(interactionWriteProvider(_key).notifier);
    final ok = await controller.submit(
      action,
      onAlreadyHandled: (error) async {
        _conflictMessage = error.message;
        _conflictStillPending = true;
        ref.invalidate(interactionProvider(_key));
        final fresh = await ref.read(interactionProvider(_key).future);
        _conflictStillPending = fresh?.isPending ?? false;
        await _refreshInbox();
      },
    );
    if (!mounted || !ok) return;
    final state = ref.read(interactionWriteProvider(_key));
    if (state is! SubmitSuccess<Interaction>) return;
    _removeFromInbox();
    Navigator.of(context).pop();
    showAppToast(context, overlay: overlay, message: message);
  }

  Future<void> _refreshInbox() async {
    final company = ref.read(activeCompanyProvider);
    if (company == null) return;
    await ref.read(inboxProvider(company.id).notifier).refresh(silent: true);
  }

  void _removeFromInbox() {
    final item = widget.attention;
    final company = ref.read(activeCompanyProvider);
    if (item == null || company == null) return;
    ref.read(inboxProvider(company.id).notifier).removeItem(item.id);
  }

  Future<void> _close() async {
    if (!mounted) return;
    if (_hasInput && !await _confirmDiscard()) return;
    if (mounted) Navigator.of(context).pop();
  }

  /// Hard server limit for `otherText` and reason fields.
  static const _maxAnswerLength = 100000;

  void _syncLocked() {
    // The sheet's guard rebuilds on notification; keep that out of build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.locked.value = _hasInput;
    });
  }

  bool get _hasInput =>
      _dirty &&
      (_reason.text.trim().isNotEmpty ||
          _checked.isNotEmpty ||
          _selected.values.any((set) => set.isNotEmpty) ||
          _texts.values.any((controller) => controller.text.trim().isNotEmpty));

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this answer?'),
        content: const Text('Your answer has not been sent yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Uri? _webUrl() {
    final session = ref.read(sessionControllerProvider);
    if (session is! SignedIn) return null;
    final href =
        widget.attention?.subject.href ??
        '/issues/${Uri.encodeComponent(widget.issueId)}';
    return webUrlFor(session.baseUrl, href);
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
}

class _ChoiceMark extends StatelessWidget {
  const new({required this.selected, required this.multi});

  final bool selected;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? pp.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(multi ? 5 : 11),
        border: Border.all(color: selected ? pp.accent : pp.line, width: 1.5),
      ),
      child: selected
          ? const Center(
              child: AppIcon(AppIconName.check, size: 14, color: Colors.white),
            )
          : null,
    );
  }
}

/// Answers from an `ask_user_questions` result, with tolerant parsing.
List<Map<String, Object?>> asAnswerMaps(Map<String, Object?> result) => [
  for (final entry in asList(result['answers']))
    if (entry is Map) entry.cast<String, Object?>(),
];

/// String items of a JSON list, dropping anything else.
List<String> asStringList(Object? value) => [
  for (final entry in asList(value))
    if (entry is String) entry,
];
