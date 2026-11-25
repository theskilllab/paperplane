import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/agent.dart';
import 'package:paperplane/api/models/approval.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/api/models/health.dart';
import 'package:paperplane/api/models/interaction.dart';
import 'package:paperplane/api/models/issue.dart';
import 'package:paperplane/api/models/project.dart';
import 'package:paperplane/api/models/session_info.dart';
import 'package:paperplane/data/agent_repository.dart';
import 'package:paperplane/data/approval_repository.dart';
import 'package:paperplane/data/company_repository.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/inbox_repository.dart';
import 'package:paperplane/data/interaction_repository.dart';
import 'package:paperplane/data/issue_repository.dart';
import 'package:paperplane/data/project_repository.dart';
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

  /// When set, list and find throw this instead.
  ApiError? listError;

  /// When true and [writeError] is an [AlreadyHandled], the write resolves the
  /// stored row before throwing. Models a 409 that followed a successful
  /// write, so a re-read shows a row that is no longer pending.
  bool resolveOnConflict = false;

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
    if (listError case final error?) throw error;
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
    _throwWriteError(issueId, interactionId);
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
    _throwWriteError(issueId, interactionId);
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
    _throwWriteError(issueId, interactionId);
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

  void _throwWriteError(String issueId, String interactionId) {
    final error = writeError;
    if (error == null) return;
    if (resolveOnConflict && error is AlreadyHandled) {
      final rows = interactions;
      final index = rows?.indexWhere((row) => row.id == interactionId) ?? -1;
      if (rows != null && index >= 0) {
        rows[index] = rows[index].copyWith(
          status: InteractionStatus.accepted,
          result: const {'version': 1, 'outcome': 'accepted'},
          resolvedAt: _now(),
        );
      }
    }
    throw error;
  }

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

/// [AgentRepository] with canned data.
class FakeAgentRepository with FakeBehavior implements AgentRepository {
  /// Replaces the list. Null serves the demo agents.
  List<Agent>? agents;

  @override
  Future<List<Agent>> listAgents(String companyId) async {
    await simulate();
    return agents ?? Agent.listFromJson(demoAgentsJson);
  }
}

/// [ProjectRepository] with canned data.
class FakeProjectRepository with FakeBehavior implements ProjectRepository {
  /// Replaces the list. Null serves the demo projects.
  List<Project>? projects;

  @override
  Future<List<Project>> listProjects(String companyId) async {
    await simulate();
    return projects ?? Project.listFromJson(demoProjectsJson);
  }
}

/// Issues the demo feed links to (S6 row-tap) plus the two sample threads.
const _demoIssueIdentifiers = {
  'ACM-12',
  'GLX-4',
  'ACM-9',
  'ACM-15',
  'ACM-21',
  'ACM-30',
};

/// [IssueRepository] with demo threads and the server's de-duplication rule
/// for `clientRequestId`.
class FakeIssueRepository with FakeBehavior implements IssueRepository {
  /// Creates the repository. [now] stamps new comments.
  new({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, List<IssueComment>> _threads = {};
  final Map<String, ({String body, IssueComment comment})> _byRequestId = {};
  final Map<String, Issue> _created = {};
  int _nextId = 1;

  /// Replaces the issue served for any id.
  Issue? issue;

  /// Replaces the thread of every issue (oldest first).
  List<IssueComment>? thread;

  /// When set, the next [postComment] throws this once, then clears it.
  ApiError? failNextPost;

  /// When set, the next [createIssue] throws this once, then clears it.
  ApiError? failNextCreate;

  /// When true, [createIssue] answers with an issue that has no id, the
  /// fallback case S7 AC4 describes.
  bool createWithoutId = false;

  /// Bodies the server accepted, in order, for assertions.
  final List<String> postedBodies = [];

  /// Issues [createIssue] returned, oldest first.
  final List<Issue> created = [];

  /// Number of [createIssue] calls, including failed ones.
  int createCalls = 0;

  /// Last fields [createIssue] received, for assertions.
  String? lastCreateCompanyId;

  /// Last title [createIssue] received.
  String? lastCreateTitle;

  /// Last description [createIssue] received.
  String? lastCreateDescription;

  /// Last assignee id [createIssue] received.
  String? lastCreateAssigneeId;

  /// Last project id [createIssue] received.
  String? lastCreateProjectId;

  /// Number of [fetchComments] calls.
  int commentFetches = 0;

  String _identifier(String issueId) => issueId.startsWith('issue-')
      ? issueId.substring(6).toUpperCase()
      : issueId;

  List<IssueComment> _thread(String issueId) {
    if (_created.containsKey(issueId)) {
      return _threads.putIfAbsent(issueId, () => <IssueComment>[]);
    }
    final replaced = thread;
    if (replaced != null) return replaced;
    final key = _identifier(issueId);
    return _threads.putIfAbsent(
      key,
      () => IssueComment.listFromJson(demoCommentsJson(key)),
    );
  }

  @override
  Future<Issue> fetchIssue(String issueId) async {
    await simulate();
    if (_created[issueId] case final created?) return created;
    final replaced = issue;
    if (replaced != null) return replaced;
    final key = _identifier(issueId);
    if (!_demoIssueIdentifiers.contains(key)) throw const NotFound();
    return Issue.fromJson(demoIssueJson(key));
  }

  @override
  Future<Issue> createIssue({
    required String companyId,
    required String title,
    String? description,
    String? assigneeAgentId,
    String? projectId,
  }) async {
    await simulate();
    createCalls++;
    lastCreateCompanyId = companyId;
    lastCreateTitle = title;
    lastCreateDescription = description;
    lastCreateAssigneeId = assigneeAgentId;
    lastCreateProjectId = projectId;
    if (failNextCreate case final error?) {
      failNextCreate = null;
      throw error;
    }
    final number = 100 + createCalls;
    final issue = Issue(
      id: createWithoutId ? '' : 'issue-created-$number',
      identifier: 'ACM-$number',
      title: title,
      companyId: companyId,
      status: assigneeAgentId == null ? IssueStatus.backlog : IssueStatus.todo,
      description: description,
      assigneeAgentId: assigneeAgentId,
      projectId: projectId,
      projectName: _projectName(projectId),
    );
    if (issue.id.isNotEmpty) _created[issue.id] = issue;
    created.add(issue);
    return issue;
  }

  String? _projectName(String? projectId) {
    if (projectId == null) return null;
    for (final project in demoProjectsJson) {
      if (project['id'] == projectId) return project['name']! as String;
    }
    return null;
  }

  @override
  Future<CommentPage> fetchComments(
    String issueId, {
    String? before,
    int limit = kCommentPageSize,
  }) async {
    commentFetches++;
    await simulate();
    final all = _thread(issueId);
    // The real server caps one page at [kCommentServerCap].
    final size = limit > kCommentServerCap ? kCommentServerCap : limit;
    var end = all.length;
    if (before != null) {
      final at = all.indexWhere((c) => c.id == before);
      // Like the server: a missing anchor answers an empty page.
      if (at < 0) return const CommentPage(comments: [], hasEarlier: false);
      end = at;
    }
    final start = end - size < 0 ? 0 : end - size;
    return CommentPage(
      comments: all.sublist(start, end),
      hasEarlier: start > 0,
    );
  }

  @override
  Future<IssueComment> postComment(
    String issueId, {
    required String body,
    required String clientRequestId,
  }) async {
    await simulate();
    if (failNextPost case final error?) {
      failNextPost = null;
      throw error;
    }
    final existing = _byRequestId[clientRequestId];
    if (existing != null) {
      if (existing.body == body) return existing.comment;
      throw const Server(409);
    }
    final comment = IssueComment(
      id: 'new-${_nextId++}',
      body: body,
      authorKind: CommentAuthorKind.user,
      authorUserId: 'user-demo-1',
      createdAt: _now(),
      clientRequestId: clientRequestId,
    );
    _byRequestId[clientRequestId] = (body: body, comment: comment);
    postedBodies.add(body);
    _thread(issueId).add(comment);
    return comment;
  }
}
