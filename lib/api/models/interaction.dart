import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// Kind of an issue-thread interaction (`issue_thread_interactions.kind`).
///
/// The server has six kinds. Only four may be resolved inside the app
/// (PRD S5 AC1, amended by THE-215 §7); the rest open in Paperclip.
enum InteractionKind {
  /// The agent proposes tasks the user can create in one batch.
  suggestTasks('suggest_tasks'),

  /// A questions form: choices, multi-select or free text.
  askUserQuestions('ask_user_questions'),

  /// A plain confirmation.
  requestConfirmation('request_confirmation'),

  /// A confirmation with a checklist.
  requestCheckboxConfirmation('request_checkbox_confirmation'),

  /// Per-item verdicts. Opens in Paperclip.
  requestItemVerdicts('request_item_verdicts'),

  /// A connection request. Opens in Paperclip.
  connectionIntent('connection_intent'),

  /// A kind this app version does not know.
  unknown('');

  new(this.wire);

  /// Value on the wire.
  final String wire;

  /// Parses the wire value; unknown values become [unknown].
  static InteractionKind parse(String? value) {
    for (final kind in values) {
      if (kind != unknown && kind.wire == value) return kind;
    }
    return unknown;
  }

  /// Short label for a heading.
  String get label => switch (this) {
    suggestTasks => 'Suggested tasks',
    askUserQuestions => 'Question',
    requestConfirmation => 'Confirmation',
    requestCheckboxConfirmation => 'Checklist',
    requestItemVerdicts => 'Review',
    connectionIntent => 'Connection request',
    unknown => 'Question',
  };
}

/// Status of an interaction.
enum InteractionStatus {
  /// Waiting for the user.
  pending('pending'),

  /// Accepted (confirmations and suggested tasks).
  accepted('accepted'),

  /// Rejected by the user.
  rejected('rejected'),

  /// Answered (questions).
  answered('answered'),

  /// Withdrawn or cancelled.
  cancelled('cancelled'),

  /// Expired on the server.
  expired('expired'),

  /// A status this app version does not know.
  unknown('');

  new(this.wire);

  /// Value on the wire.
  final String wire;

  /// Parses the wire value; unknown values become [unknown].
  static InteractionStatus parse(String? value) {
    for (final status in values) {
      if (status != unknown && status.wire == value) return status;
    }
    return unknown;
  }

  /// Short label for the final state.
  String get label => switch (this) {
    pending => 'Pending',
    accepted => 'Accepted',
    rejected => 'Rejected',
    answered => 'Answered',
    cancelled => 'Cancelled',
    expired => 'Expired',
    unknown => 'Closed',
  };

  /// True while a response can still be sent.
  bool get isPending => this == pending;
}

/// Whether the app can resolve an interaction inside its own sheet.
enum InteractionSupport {
  /// Render the form and send the decision from the app.
  inline,

  /// Show "Open in Paperclip" and no inline action.
  openInPaperclip,
}

/// One option of a question or checkbox.
@immutable
class InteractionOption {
  /// Creates an option.
  const new({
    required this.id,
    required this.label,
    this.description,
    this.freeText = false,
  });

  /// Parses one option tolerantly.
  factory fromJson(Map<String, Object?> json) => InteractionOption(
    id: readString(json, 'id') ?? '',
    label: readNonEmpty(json, 'label') ?? readString(json, 'id') ?? '',
    description: readNonEmpty(json, 'description'),
    freeText: readBool(json, 'freeText'),
  );

  /// Wire id.
  final String id;

  /// Display label.
  final String label;

  /// Optional help under the label.
  final String? description;

  /// True when selecting this option asks the user for text.
  final bool freeText;
}

/// Text limits for one free-text question.
@immutable
class InteractionTextRules {
  /// Creates the rules.
  const new({
    this.minLength,
    this.maxLength,
    this.numeric = false,
    this.unsupported = false,
  });

  /// Parses `textValidation` tolerantly.
  factory fromJson(Map<String, Object?> json) {
    final inputType = readString(json, 'inputType');
    final numeric = inputType == 'number' || inputType == 'integer';
    return InteractionTextRules(
      minLength: _optionalInt(json['minLength']),
      maxLength: _optionalInt(json['maxLength']),
      numeric: numeric,
      // Numeric bounds and server-side patterns need a richer form than this
      // version ships; open those in Paperclip instead of sending an invalid
      // answer.
      unsupported:
          numeric ||
          readString(json, 'pattern') != null ||
          json['minimum'] != null ||
          json['maximum'] != null,
    );
  }

  /// Minimum characters, when the server sets one.
  final int? minLength;

  /// Maximum characters, when the server sets one.
  final int? maxLength;

  /// True for number or integer answers.
  final bool numeric;

  /// True when this app cannot enforce the server's validation.
  final bool unsupported;
}

/// One question of an `ask_user_questions` interaction.
@immutable
class InteractionQuestion {
  /// Creates a question.
  const new({
    required this.id,
    required this.prompt,
    required this.required,
    required this.multiSelect,
    required this.options,
    this.helpText,
    this.textRules = const InteractionTextRules(),
    this.unsupported = false,
  });

  /// Question id, sent back as `questionId`.
  final String id;

  /// Prompt text.
  final String prompt;

  /// True when an answer is required.
  final bool required;

  /// True for `multi` selection.
  final bool multiSelect;

  /// Choices, including a free-text option when the server allows one.
  final List<InteractionOption> options;

  /// Optional help text.
  final String? helpText;

  /// Text limits and unsupported modes.
  final InteractionTextRules textRules;

  /// True when this app cannot render this question faithfully.
  final bool unsupported;

  /// The free-text option, if the question has one.
  InteractionOption? get freeTextOption {
    for (final option in options) {
      if (option.freeText) return option;
    }
    return null;
  }

  /// True when the only answer is free text.
  bool get isFreeTextOnly => options.length == 1 && options.single.freeText;
}

/// A questions form (`ask_user_questions`).
@immutable
class InteractionQuestionForm {
  /// Creates a form.
  const new({
    required this.questions,
    this.title,
    this.description,
    this.submitLabel,
    this.questionSet = const {},
  });

  /// Parses the payload tolerantly.
  factory fromPayload(Map<String, Object?> payload) {
    final questionSet = asMap(payload['questionSet']);
    final canonical = <String, Map<String, Object?>>{
      for (final entry in asList(questionSet['questions']))
        if (asMap(entry)['id'] case final String id) id: asMap(entry),
    };
    final stored = asList(payload['questions']);
    final questions = <InteractionQuestion>[];
    if (stored.isEmpty) {
      for (final entry in canonical.values) {
        final parsed = _fromCanonical(entry);
        if (parsed != null) questions.add(parsed);
      }
    } else {
      for (final entry in stored) {
        final parsed = _fromStored(asMap(entry), canonical[asMap(entry)['id']]);
        if (parsed != null) questions.add(parsed);
      }
    }
    return InteractionQuestionForm(
      questions: questions,
      title:
          readNonEmpty(payload, 'title') ?? readNonEmpty(questionSet, 'title'),
      description: readNonEmpty(questionSet, 'description'),
      submitLabel:
          readNonEmpty(payload, 'submitLabel') ??
          readNonEmpty(questionSet, 'submitLabel'),
      questionSet: questionSet,
    );
  }

  static InteractionQuestion? _fromStored(
    Map<String, Object?> json,
    Map<String, Object?>? canonical,
  ) {
    final id = readNonEmpty(json, 'id');
    final prompt = readNonEmpty(json, 'prompt');
    if (id == null || prompt == null) return null;
    final options = [
      for (final entry in asList(json['options']))
        InteractionOption.fromJson(asMap(entry)),
    ];
    final answerMode = canonical == null
        ? null
        : readString(canonical, 'answerMode');
    final textRules = InteractionTextRules.fromJson(
      asMap(canonical?['textValidation']),
    );
    var unsupported = options.isEmpty || textRules.unsupported;
    // A canonical text answer needs the free-text option the server stores
    // beside it. A mismatch means this row is not safe to answer from here.
    if (answerMode == 'text' && !options.any((option) => option.freeText)) {
      unsupported = true;
    }
    if (canonical?['initialText'] != null) unsupported = true;
    return InteractionQuestion(
      id: id,
      prompt: prompt,
      required: readBool(json, 'required', fallback: true),
      multiSelect: readString(json, 'selectionMode') == 'multi',
      options: options,
      helpText:
          readNonEmpty(json, 'helpText') ??
          (canonical == null ? null : readNonEmpty(canonical, 'helpText')) ??
          (canonical == null ? null : readNonEmpty(canonical, 'header')),
      textRules: textRules,
      unsupported: unsupported,
    );
  }

  static InteractionQuestion? _fromCanonical(Map<String, Object?> json) {
    final id = readNonEmpty(json, 'id');
    final prompt = readNonEmpty(json, 'prompt');
    if (id == null || prompt == null) return null;
    final textRules = InteractionTextRules.fromJson(
      asMap(json['textValidation']),
    );
    final mode = readString(json, 'answerMode');
    final options = [
      for (final entry in asList(json['options']))
        InteractionOption.fromJson(asMap(entry)),
    ];
    if (mode == 'text') {
      options.add(
        const InteractionOption(
          id: 'paperclip_text_answer',
          label: 'Type an answer',
          freeText: true,
        ),
      );
    }
    return InteractionQuestion(
      id: id,
      prompt: prompt,
      required: readBool(json, 'required', fallback: true),
      multiSelect: mode == 'multi_select',
      options: options,
      helpText: readNonEmpty(json, 'helpText') ?? readNonEmpty(json, 'header'),
      textRules: textRules,
      unsupported:
          options.isEmpty ||
          textRules.unsupported ||
          json['initialText'] != null,
    );
  }

  /// Questions in display order.
  final List<InteractionQuestion> questions;

  /// Optional form heading.
  final String? title;

  /// Optional form help.
  final String? description;

  /// Custom submit label.
  final String? submitLabel;

  /// The canonical presentation, kept for contract tests.
  final Map<String, Object?> questionSet;

  /// True when every question can be answered in this app.
  bool get isSupported =>
      questions.isNotEmpty && questions.every((q) => !q.unsupported);
}

/// A plain confirmation (`request_confirmation` without a governed action).
@immutable
class InteractionConfirmation {
  /// Creates the confirmation.
  const new({
    required this.prompt,
    this.acceptLabel,
    this.rejectLabel,
    this.detailsMarkdown,
    this.rejectRequiresReason = false,
    this.rejectReasonLabel,
    this.allowDeclineReason = true,
    this.declineReasonPlaceholder,
    this.targetLabel,
    this.targetType,
    this.hasToolAction = false,
    this.hasSecretProposal = false,
    this.hasConnectionAuthorization = false,
    this.hasNonPlainKeys = false,
    this.isStaleTarget = false,
  });

  /// Parses the payload and result tolerantly.
  factory fromPayload(
    Map<String, Object?> payload, {
    Map<String, Object?> result = const {},
  }) {
    final target = asMap(payload['target']);
    return InteractionConfirmation(
      prompt: readNonEmpty(payload, 'prompt') ?? '',
      acceptLabel: readNonEmpty(payload, 'acceptLabel'),
      rejectLabel: readNonEmpty(payload, 'rejectLabel'),
      detailsMarkdown: readNonEmpty(payload, 'detailsMarkdown'),
      rejectRequiresReason: readBool(payload, 'rejectRequiresReason'),
      rejectReasonLabel: readNonEmpty(payload, 'rejectReasonLabel'),
      allowDeclineReason: readBool(
        payload,
        'allowDeclineReason',
        fallback: true,
      ),
      declineReasonPlaceholder: readNonEmpty(
        payload,
        'declineReasonPlaceholder',
      ),
      targetLabel: readNonEmpty(target, 'label'),
      targetType: readNonEmpty(target, 'type'),
      hasToolAction: payload['toolAction'] != null,
      hasSecretProposal: payload['secretProposal'] != null,
      hasConnectionAuthorization:
          payload['connectionAuthorization'] != null ||
          payload['connection_authorization'] != null,
      hasNonPlainKeys: !payload.keys.every(plainPayloadKeys.contains),
      isStaleTarget:
          readString(result, 'outcome') == 'stale_target' ||
          result['staleTarget'] != null,
    );
  }

  /// Payload keys a confirmation may carry and still resolve inline.
  ///
  /// This is an allowlist: a governed key the server adds later, such as
  /// `qualityReview`, opens in Paperclip instead of silently gaining an
  /// inline Approve. The server's Zod object strips unknown keys, so the set
  /// is well defined.
  static const plainPayloadKeys = <String>{
    'version',
    'prompt',
    'acceptLabel',
    'rejectLabel',
    'rejectRequiresReason',
    'rejectReasonLabel',
    'allowDeclineReason',
    'declineReasonPlaceholder',
    'detailsMarkdown',
    'supersedeOnUserComment',
    'target',
  };

  /// Question text.
  final String prompt;

  /// Custom accept label.
  final String? acceptLabel;

  /// Custom reject label.
  final String? rejectLabel;

  /// Safe Markdown shown above the buttons.
  final String? detailsMarkdown;

  /// True when rejecting needs a reason.
  final bool rejectRequiresReason;

  /// Label of the reason field.
  final String? rejectReasonLabel;

  /// True when a rejection reason is allowed at all.
  final bool allowDeclineReason;

  /// Placeholder of the reason field.
  final String? declineReasonPlaceholder;

  /// Label of the target document, when the server sends one.
  final String? targetLabel;

  /// Target type (`issue_document`, `custom`).
  final String? targetType;

  /// True for a tool-action confirmation.
  final bool hasToolAction;

  /// True for a secret-proposal confirmation.
  final bool hasSecretProposal;

  /// True for a connection-authorization confirmation.
  final bool hasConnectionAuthorization;

  /// True when the payload holds a key outside [plainPayloadKeys].
  final bool hasNonPlainKeys;

  /// True when the target changed after the request was made.
  final bool isStaleTarget;

  /// True when the app may show inline buttons for this confirmation.
  ///
  /// An allowlist, not a denylist: every payload key must be a known plain
  /// key. A `qualityReview` or any future governed key therefore fails
  /// closed, and a stale target is still excluded.
  bool get isPlain => !hasNonPlainKeys && !isStaleTarget;
}

/// One task in a `suggest_tasks` payload.
@immutable
class SuggestedTask {
  /// Creates a task.
  const new({
    required this.clientKey,
    required this.title,
    this.description,
    this.priority,
    this.parentClientKey,
  });

  /// Parses one task tolerantly.
  factory fromJson(Map<String, Object?> json) => SuggestedTask(
    clientKey: readString(json, 'clientKey') ?? '',
    title: readNonEmpty(json, 'title') ?? '',
    description: readNonEmpty(json, 'description'),
    priority: readNonEmpty(json, 'priority'),
    parentClientKey: readNonEmpty(json, 'parentClientKey'),
  );

  /// Stable key the accept call sends back.
  final String clientKey;

  /// Task title.
  final String title;

  /// Task description.
  final String? description;

  /// `critical`, `high`, `medium` or `low`.
  final String? priority;

  /// Parent task, when the server groups them.
  final String? parentClientKey;
}

/// A `suggest_tasks` interaction.
@immutable
class InteractionSuggestedTasks {
  /// Creates the list.
  const new(this.tasks);

  /// Parses the payload tolerantly.
  factory fromPayload(Map<String, Object?> payload) =>
      InteractionSuggestedTasks([
        for (final entry in asList(payload['tasks']))
          SuggestedTask.fromJson(asMap(entry)),
      ]);

  /// Tasks the server will create on accept.
  final List<SuggestedTask> tasks;

  /// True when there is at least one valid task.
  bool get isSupported =>
      tasks.isNotEmpty &&
      tasks.every((task) => task.clientKey.isNotEmpty && task.title.isNotEmpty);
}

/// A checklist (`request_checkbox_confirmation`).
@immutable
class InteractionChecklist {
  /// Creates the checklist.
  const new({
    required this.prompt,
    required this.options,
    required this.defaultSelected,
    this.detailsMarkdown,
    this.minSelected = 0,
    this.maxSelected,
    this.acceptLabel,
    this.rejectLabel,
    this.rejectRequiresReason = false,
    this.rejectReasonLabel,
    this.allowDeclineReason = true,
    this.declineReasonPlaceholder,
    this.targetLabel,
    this.targetType,
  });

  /// Parses the payload tolerantly.
  factory fromPayload(Map<String, Object?> payload) {
    final target = asMap(payload['target']);
    return InteractionChecklist(
      prompt: readNonEmpty(payload, 'prompt') ?? '',
      options: [
        for (final entry in asList(payload['options']))
          InteractionOption.fromJson(asMap(entry)),
      ],
      defaultSelected: {
        for (final entry in asList(payload['defaultSelectedOptionIds']))
          if (entry is String) entry,
      },
      detailsMarkdown: readNonEmpty(payload, 'detailsMarkdown'),
      minSelected: readInt(payload, 'minSelected'),
      maxSelected: _optionalInt(payload['maxSelected']),
      acceptLabel: readNonEmpty(payload, 'acceptLabel'),
      rejectLabel: readNonEmpty(payload, 'rejectLabel'),
      rejectRequiresReason: readBool(payload, 'rejectRequiresReason'),
      rejectReasonLabel: readNonEmpty(payload, 'rejectReasonLabel'),
      allowDeclineReason: readBool(
        payload,
        'allowDeclineReason',
        fallback: true,
      ),
      declineReasonPlaceholder: readNonEmpty(
        payload,
        'declineReasonPlaceholder',
      ),
      targetLabel: readNonEmpty(target, 'label'),
      targetType: readNonEmpty(target, 'type'),
    );
  }

  /// Question text.
  final String prompt;

  /// Checkbox options.
  final List<InteractionOption> options;

  /// Options selected when the sheet opens.
  final Set<String> defaultSelected;

  /// Safe Markdown shown above the checklist.
  final String? detailsMarkdown;

  /// Minimum number of selected options.
  final int minSelected;

  /// Maximum number of selected options, or null for no limit.
  final int? maxSelected;

  /// Custom accept label.
  final String? acceptLabel;

  /// Custom reject label.
  final String? rejectLabel;

  /// True when rejecting needs a reason.
  final bool rejectRequiresReason;

  /// Label of the reason field.
  final String? rejectReasonLabel;

  /// True when a rejection reason is allowed at all.
  final bool allowDeclineReason;

  /// Placeholder of the reason field.
  final String? declineReasonPlaceholder;

  /// Label of the target document, when the server sends one.
  final String? targetLabel;

  /// Target type (`issue_document`, `custom`).
  final String? targetType;

  /// True when the app can render the checklist.
  bool get isSupported =>
      options.isNotEmpty &&
      minSelected >= 0 &&
      (maxSelected == null || maxSelected! >= minSelected) &&
      options.every((option) => option.id.isNotEmpty);

  /// True when [selected] satisfies the server's bounds.
  bool isValid(Set<String> selected) =>
      selected.length >= minSelected &&
      (maxSelected == null || selected.length <= maxSelected!);
}

/// One issue-thread interaction (`GET /issues/{id}/interactions`).
@immutable
class Interaction {
  /// Creates an interaction.
  const new({
    required this.id,
    required this.kind,
    required this.status,
    required this.payload,
    this.rawKind = '',
    this.issueId = '',
    this.companyId = '',
    this.title,
    this.summary,
    this.result = const {},
    this.createdAt,
    this.updatedAt,
    this.resolvedAt,
    this.acceptanceBlocker,
  });

  /// Parses one interaction tolerantly.
  factory fromJson(Map<String, Object?> json) {
    final raw = readString(json, 'kind') ?? '';
    return Interaction(
      id: readString(json, 'id') ?? '',
      issueId: readString(json, 'issueId') ?? '',
      companyId: readString(json, 'companyId') ?? '',
      rawKind: raw,
      kind: InteractionKind.parse(raw),
      status: InteractionStatus.parse(readString(json, 'status')),
      title: readNonEmpty(json, 'title'),
      summary: readNonEmpty(json, 'summary'),
      payload: asMap(json['payload']),
      result: asMap(json['result']),
      createdAt: readDate(json, 'createdAt'),
      updatedAt: readDate(json, 'updatedAt'),
      resolvedAt: readDate(json, 'resolvedAt'),
      acceptanceBlocker: readNonEmpty(json, 'acceptanceBlocker'),
    );
  }

  /// Interaction id.
  final String id;

  /// Issue the interaction belongs to.
  final String issueId;

  /// Company the interaction belongs to.
  final String companyId;

  /// Kind exactly as the server sent it.
  final String rawKind;

  /// Parsed kind.
  final InteractionKind kind;

  /// Current status.
  final InteractionStatus status;

  /// Optional title.
  final String? title;

  /// Optional summary.
  final String? summary;

  /// Kind-specific payload.
  final Map<String, Object?> payload;

  /// Resolution result, when the server sends one.
  final Map<String, Object?> result;

  /// When it was created.
  final DateTime? createdAt;

  /// Last change.
  final DateTime? updatedAt;

  /// When it was resolved.
  final DateTime? resolvedAt;

  /// Non-null while a source run's workspace is still syncing.
  final String? acceptanceBlocker;

  /// True while the user can still answer it.
  bool get isPending => status.isPending;

  /// True while the server says a source run's workspace is still syncing.
  ///
  /// The server rejects accept with a 409 in this state. Inline accept must
  /// stay disabled until a re-read clears the blocker.
  bool get acceptBlocked => acceptanceBlocker != null;

  /// Copies the interaction with a new status, result or both.
  Interaction copyWith({
    InteractionStatus? status,
    Map<String, Object?>? result,
    DateTime? resolvedAt,
  }) => Interaction(
    id: id,
    issueId: issueId,
    companyId: companyId,
    rawKind: rawKind,
    kind: kind,
    status: status ?? this.status,
    title: title,
    summary: summary,
    payload: payload,
    result: result ?? this.result,
    createdAt: createdAt,
    updatedAt: updatedAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    acceptanceBlocker: acceptanceBlocker,
  );

  /// Heading for the sheet.
  String get heading {
    final title = this.title;
    if (title != null && title.isNotEmpty) return title;
    final summary = this.summary;
    if (summary != null && summary.isNotEmpty) return summary;
    return kind.label;
  }

  /// Parsed questions form.
  InteractionQuestionForm get questionForm =>
      InteractionQuestionForm.fromPayload(payload);

  /// Parsed confirmation.
  InteractionConfirmation get confirmation =>
      InteractionConfirmation.fromPayload(payload, result: result);

  /// Parsed suggested tasks.
  InteractionSuggestedTasks get suggestedTasks =>
      InteractionSuggestedTasks.fromPayload(payload);

  /// Parsed checklist.
  InteractionChecklist get checklist =>
      InteractionChecklist.fromPayload(payload);

  /// Result outcome, when present.
  String? get resultOutcome => readNonEmpty(result, 'outcome');

  /// True when the app may render the controls for this item.
  bool get canResolveInline {
    if (!isPending) return false;
    return switch (kind) {
      InteractionKind.askUserQuestions => questionForm.isSupported,
      InteractionKind.requestConfirmation => confirmation.isPlain,
      InteractionKind.suggestTasks => suggestedTasks.isSupported,
      InteractionKind.requestCheckboxConfirmation => checklist.isSupported,
      InteractionKind.requestItemVerdicts ||
      InteractionKind.connectionIntent ||
      InteractionKind.unknown => false,
    };
  }

  /// The support decision for the sheet.
  InteractionSupport get support => canResolveInline
      ? InteractionSupport.inline
      : InteractionSupport.openInPaperclip;

  /// Human-readable final state, when the item is no longer pending.
  String get finalStateLabel {
    final outcome = resultOutcome;
    if (outcome == 'stale_target') return 'The target changed';
    if (outcome == 'superseded_by_comment') return 'Superseded';
    if (outcome == 'issue_closed') return 'The issue closed';
    return status.label;
  }
}

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
