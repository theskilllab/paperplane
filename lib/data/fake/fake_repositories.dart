import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/approval.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/api/models/health.dart';
import 'package:paperplane/api/models/interaction.dart';
import 'package:paperplane/api/models/session_info.dart';
import 'package:paperplane/data/approval_repository.dart';
import 'package:paperplane/data/company_repository.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/inbox_repository.dart';
import 'package:paperplane/data/interaction_repository.dart';
import 'package:paperplane/data/session_repository.dart';

/// Shared knobs of the fake repositories.
///
/// Demo mode leaves them at the defaults. Tests set [failWith] to walk a
/// screen through its offline, 401, 403 and 5xx states, and [latency] to see
/// loading states.
mixin FakeBehavior {
  /// Delay before every answer.
  Duration latency = Duration.zero;

  /// When set, every call throws this instead of answering.
  ApiError? failWith;

  /// Number of calls made, for assertions.
  int calls = 0;

  /// Call at the start of each repository method.
  Future<void> simulate() async {
    calls++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failWith case final error?) throw error;
  }
}

/// [SessionRepository] with canned data.
class FakeSessionRepository with FakeBehavior implements SessionRepository {
  /// Number of times [revokeCurrentKey] ran.
  int revokeCount = 0;

  @override
  Future<HealthInfo> health() async {
    await simulate();
    return HealthInfo.fromJson(demoHealthJson);
  }

  @override
  Future<SessionInfo> me() async {
    await simulate();
    return SessionInfo.fromJson(demoSessionJson);
  }

  @override
  Future<void> revokeCurrentKey() async {
    await simulate();
    revokeCount++;
  }
}

/// [CompanyRepository] with canned data.
class FakeCompanyRepository with FakeBehavior implements CompanyRepository {
  /// Replaces the list. Null serves both demo companies.
  List<Company>? companies;

  /// What a cold start would find on disk. Null means nothing cached.
  List<Company>? cached;

  @override
  Future<List<Company>> listCompanies() async {
    await simulate();
    return companies ?? Company.listFromJson(demoCompaniesJson);
  }

  @override
  List<Company>? cachedCompanies() => cached;
}

/// [InboxRepository] with canned data covering every `sourceKind`.
class FakeInboxRepository with FakeBehavior implements InboxRepository {
  /// Creates the repository. [now] anchors timestamps; tests pass a fixed one.
  new({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Replaces the feed of every company. Null serves each company's own demo
  /// feed.
  AttentionFeed? feed;

  /// What a cold start would find on disk. Null means nothing cached.
  CachedFeed? cached;

  @override
  CachedFeed? cachedFeed(String companyId) =>
      cached?.companyId == companyId ? cached : null;

  @override
  Future<AttentionFeed> fetchAttention(
    String companyId, {
    int limit = 100,
  }) async {
    await simulate();
    return feed ??
        AttentionFeed.fromJson(demoAttentionJsonFor(companyId, _now()));
  }

  @override
  Future<Map<String, String>> agentNames(String companyId) async {
    await simulate();
    return demoAgentNames;
  }
}

/// [ApprovalRepository] with canned data.
class FakeApprovalRepository with FakeBehavior implements ApprovalRepository {
  /// Creates the repository. [now] anchors timestamps and decisions.
  new({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Replaces the fetched approval. Null serves the demo approval for the id.
  Approval? approval;

  /// Replaces the linked issues. Null serves the demo list for the id.
  List<LinkedIssue>? issues;

  /// Number of fetch calls.
  int fetchCalls = 0;

  /// When set, approve and reject throw this instead (for G10, 403, offline).
  ApiError? decisionError;

  /// Number of approve calls.
  int approveCalls = 0;

  /// Number of reject calls.
  int rejectCalls = 0;

  /// Note sent with the last decision.
  String? lastDecisionNote;

  @override
  Future<Approval> fetch(String approvalId) async {
    await simulate();
    fetchCalls++;
    return approval ?? Approval.fromJson(demoApprovalJson(approvalId, _now()));
  }

  @override
  Future<List<LinkedIssue>> linkedIssues(String approvalId) async {
    await simulate();
    return issues ??
        [
          for (final entry in demoApprovalIssuesJson(approvalId))
            LinkedIssue.fromJson((entry! as Map).cast<String, Object?>()),
        ];
  }

  @override
  Future<Approval> approve(String approvalId, {String? decisionNote}) async {
    await simulate();
    if (decisionError case final error?) throw error;
    approveCalls++;
    return _decide(approvalId, ApprovalStatus.approved, decisionNote);
  }

  @override
  Future<Approval> reject(String approvalId, {String? decisionNote}) async {
    await simulate();
    if (decisionError case final error?) throw error;
    rejectCalls++;
    return _decide(approvalId, ApprovalStatus.rejected, decisionNote);
  }

  Approval _decide(
    String approvalId,
    ApprovalStatus status,
    String? decisionNote,
  ) {
    lastDecisionNote = decisionNote;
    final current =
        approval ?? Approval.fromJson(demoApprovalJson(approvalId, _now()));
    final updated = current.copyWith(
      status: status,
      decisionNote: decisionNote,
      decidedByUserId: 'user-demo-1',
      decidedAt: _now(),
    );
    approval = updated;
    return updated;
  }
}

/// [InteractionRepository] with canned data.
class FakeInteractionRepository
    with FakeBehavior
    implements InteractionRepository {
  /// Creates the repository. [now] anchors demo timestamps and
  /// [interactions] replaces the demo rows.
  new({DateTime Function()? now, this.interactions})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Replaces the list for every issue. Null serves the demo interactions.
  List<Interaction>? interactions;

  /// When set, respond, accept and reject throw this instead.
  ApiError? writeError;

  /// Number of list calls.
  int listCalls = 0;

  /// Number of respond calls.
  int respondCalls = 0;

  /// Number of accept calls.
  int acceptCalls = 0;

  /// Number of reject calls.
  int rejectCalls = 0;

  /// Answers sent with the last respond call.
  List<QuestionAnswer>? lastAnswers;

  /// Client keys sent with the last accept call.
  List<String>? lastClientKeys;

  /// Option ids sent with the last accept call.
  List<String>? lastOptionIds;

  /// Reason sent with the last reject call.
  String? lastReason;

  /// The row returned for one key, so tests can inspect the result.
  Interaction? _last;

  @override
  Future<List<Interaction>> list(String issueId) async {
    await simulate();
    listCalls++;
    if (interactions case final list?) {
      return [
        for (final interaction in list)
          if (interaction.issueId == issueId || interaction.issueId.isEmpty)
            interaction,
      ];
    }
    return [
      for (final entry in demoInteractionsJson(issueId, _now()))
        Interaction.fromJson((entry! as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<Interaction?> find(String issueId, String interactionId) async {
    final rows = await list(issueId);
    for (final row in rows) {
      if (row.id == interactionId) return row;
    }
    return null;
  }

  @override
  Future<Interaction> respond(
    String issueId,
    String interactionId,
    List<QuestionAnswer> answers,
  ) async {
    await simulate();
    if (writeError case final error?) throw error;
    respondCalls++;
    lastAnswers = answers;
    return _resolve(issueId, interactionId, InteractionStatus.answered, {
      'version': 1,
      'answers': [for (final answer in answers) answer.toJson()],
    });
  }

  @override
  Future<Interaction> accept(
    String issueId,
    String interactionId, {
    List<String> selectedClientKeys = const [],
    List<String> selectedOptionIds = const [],
    bool? rememberAction,
  }) async {
    await simulate();
    if (writeError case final error?) throw error;
    acceptCalls++;
    lastClientKeys = selectedClientKeys;
    lastOptionIds = selectedOptionIds;
    return _resolve(issueId, interactionId, InteractionStatus.accepted, {
      'version': 1,
      'outcome': 'accepted',
      if (selectedOptionIds.isNotEmpty) 'selectedOptionIds': selectedOptionIds,
    });
  }

  @override
  Future<Interaction> reject(
    String issueId,
    String interactionId, {
    String? reason,
  }) async {
    await simulate();
    if (writeError case final error?) throw error;
    rejectCalls++;
    lastReason = reason;
    return _resolve(issueId, interactionId, InteractionStatus.rejected, {
      'version': 1,
      'outcome': 'rejected',
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  /// The row produced by the last write.
  Interaction? get lastResolved => _last;

  Interaction _resolve(
    String issueId,
    String interactionId,
    InteractionStatus status,
    Map<String, Object?> result,
  ) {
    final current =
        _current(issueId, interactionId) ??
        Interaction(
          id: interactionId,
          issueId: issueId,
          kind: InteractionKind.unknown,
          status: InteractionStatus.pending,
          payload: const {},
        );
    final updated = current.copyWith(
      status: status,
      result: result,
      resolvedAt: _now(),
    );
    _last = updated;
    return updated;
  }

  Interaction? _current(String issueId, String interactionId) {
    for (final row in interactions ?? const <Interaction>[]) {
      if (row.issueId == issueId && row.id == interactionId) return row;
    }
    for (final entry in demoInteractionsJson(issueId, _now())) {
      final row = Interaction.fromJson((entry! as Map).cast<String, Object?>());
      if (row.id == interactionId) return row;
    }
    return null;
  }
}
