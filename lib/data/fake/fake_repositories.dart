import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/agent.dart';
import 'package:paperplane/api/models/approval.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/api/models/health.dart';
import 'package:paperplane/api/models/project.dart';
import 'package:paperplane/api/models/session_info.dart';
import 'package:paperplane/data/agent_repository.dart';
import 'package:paperplane/data/approval_repository.dart';
import 'package:paperplane/data/company_repository.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/inbox_repository.dart';
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
