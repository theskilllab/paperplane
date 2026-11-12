import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/api/models/health.dart';
import 'package:paperplane/api/models/session_info.dart';
import 'package:paperplane/data/company_repository.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/inbox_repository.dart';
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
