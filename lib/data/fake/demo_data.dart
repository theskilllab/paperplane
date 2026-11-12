/// Fake server data for demo mode and tests.
///
/// Everything here is invented. Hostnames use the reserved `.invalid` TLD,
/// names are obviously fake, and there is no token anywhere. The attention
/// feed covers all 11 `sourceKind`s the server can send, plus one kind this
/// app does not know, so the generic row is always exercised.
library;

/// Placeholder address shown in demo mode. Never contacted.
const demoBaseUrl = 'https://paperclip.demo.invalid';

/// Id of the demo company.
const demoCompanyId = 'company-demo-1';

/// Second demo company, so the switcher has something to switch.
const demoCompanyId2 = 'company-demo-2';

/// `GET /health` body.
const Map<String, Object?> demoHealthJson = {
  'status': 'ok',
  'deploymentMode': 'authenticated',
  'deploymentExposure': 'private',
};

/// `GET /cli-auth/me` body.
const Map<String, Object?> demoSessionJson = {
  'user': {
    'id': 'user-demo-1',
    'name': 'Demo Person',
    'email': 'demo@example.invalid',
  },
  'companyIds': [demoCompanyId, demoCompanyId2],
  'keyId': 'key-demo-1',
  'source': 'board_key',
};

/// `GET /companies` body.
const List<Object?> demoCompaniesJson = [
  {'id': demoCompanyId, 'name': 'Acme Demo', 'issuePrefix': 'ACM'},
  {'id': demoCompanyId2, 'name': 'Globex Demo', 'issuePrefix': 'GLX'},
];

/// `GET /companies/{id}/agents` as id → name.
const Map<String, String> demoAgentNames = {
  'agent-ceo': 'Chief Example',
  'agent-eng': 'Engineer Example',
  'agent-qa': 'Tester Example',
};

/// Wraps [items] as an attention feed body. [total] is what the server would
/// report as `totalCount`; it defaults to the number of items (no truncation).
Map<String, Object?> _feedJson(
  List<Map<String, Object?>> items,
  DateTime now, {
  int? total,
  Map<String, int>? counts,
}) {
  final derived = <String, int>{};
  for (final entry in items) {
    final kind = entry['sourceKind']! as String;
    derived[kind] = (derived[kind] ?? 0) + 1;
  }
  return {
    'items': items,
    'totalCount': total ?? items.length,
    'countsBySourceKind': counts ?? derived,
    'generatedAt': now.toUtc().toIso8601String(),
    'nextCursor': null,
  };
}

/// Builds one feed item. [now] anchors [age].
Map<String, Object?> _item(
  DateTime now,
  String id,
  String kind,
  String title, {
  String? summary,
  String? agent,
  Duration age = const Duration(hours: 1),
  String? href,
  bool inlineResolvable = false,
  String audience = 'board',
  Map<String, Object?> metadata = const {},
}) {
  final at = now.subtract(age).toUtc().toIso8601String();
  return {
    'id': id,
    'sourceKind': kind,
    'title': title,
    'summary': ?summary,
    'originAgentName': ?agent,
    'createdAt': at,
    'activityAt': at,
    'resolverAudience': audience,
    'inlineResolvable': inlineResolvable,
    'subject': {'href': href, 'metadata': metadata},
  };
}

/// The attention feed of the demo company [companyId]. Unknown ids get the
/// first company's feed. [now] anchors the timestamps.
Map<String, Object?> demoAttentionJsonFor(String companyId, DateTime now) =>
    companyId == demoCompanyId2
    ? demoSecondCompanyAttentionJson(now)
    : demoAttentionJson(now);

/// Feed of the second demo company: short, so a switch is easy to see.
Map<String, Object?> demoSecondCompanyAttentionJson(DateTime now) => _feedJson([
  _item(
    now,
    'att-g1',
    'approval',
    'Approve the Q4 hiring plan',
    age: const Duration(minutes: 30),
    href: '/GLX/approvals/appr-g1',
    inlineResolvable: true,
    metadata: {'requestedByAgentId': 'agent-ceo'},
  ),
  _item(
    now,
    'att-g2',
    'issue_thread_interaction',
    'Ship the beta on Friday?',
    agent: 'Engineer Example',
    age: const Duration(hours: 4),
    href: '/GLX/issues/GLX-4#interaction-int-g1',
  ),
  _item(
    now,
    'att-g3',
    'failed_run',
    'Run failed: deploy step timed out',
    agent: 'Engineer Example',
    age: const Duration(hours: 8),
    href: '/GLX/runs/run-g1',
  ),
], now);

/// A feed with nothing in it ("Nothing needs you").
Map<String, Object?> demoEmptyAttentionJson(DateTime now) =>
    _feedJson(const [], now);

/// A feed the server cut at its page limit: the first items of a much longer
/// list, with the true counts. Shows "Showing first N of M".
Map<String, Object?> demoTruncatedAttentionJson(DateTime now) {
  final full = demoAttentionJson(now);
  final items = (full['items']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .take(6)
      .toList();
  return _feedJson(
    items,
    now,
    total: 137,
    counts: {
      'approval': 41,
      'issue_thread_interaction': 23,
      'failed_run': 38,
      'blocker_attention': 20,
      'review': 15,
    },
  );
}

/// Builds the demo attention feed body. [now] anchors the timestamps.
Map<String, Object?> demoAttentionJson(DateTime now) {
  Map<String, Object?> item(
    String id,
    String kind,
    String title, {
    String? summary,
    String? agent,
    Duration age = const Duration(hours: 1),
    String? href,
    bool inlineResolvable = false,
    Map<String, Object?> metadata = const {},
  }) => _item(
    now,
    id,
    kind,
    title,
    summary: summary,
    agent: agent,
    age: age,
    href: href,
    inlineResolvable: inlineResolvable,
    metadata: metadata,
  );

  final items = [
    item(
      'att-01',
      'approval',
      'Hire a support agent',
      summary: 'Requests a new agent with read access to tickets.',
      age: const Duration(minutes: 12),
      href: '/ACM/approvals/appr-01',
      inlineResolvable: true,
      metadata: {'requestedByAgentId': 'agent-ceo'},
    ),
    item(
      'att-02',
      'approval',
      'Raise the monthly budget limit',
      age: const Duration(hours: 3),
      href: '/ACM/approvals/appr-02',
      inlineResolvable: true,
      metadata: {'requestedByAgentId': 'agent-eng'},
    ),
    item(
      'att-03',
      'issue_thread_interaction',
      'Which release channel should we use?',
      summary: 'Stable or beta. The agent waits for your answer.',
      agent: 'Engineer Example',
      age: const Duration(minutes: 40),
      href: '/ACM/issues/ACM-12#interaction-int-01',
    ),
    item(
      'att-04',
      'decision',
      'Pick a vendor for log storage',
      agent: 'Chief Example',
      age: const Duration(hours: 5),
      href: '/ACM/issues/ACM-9#interaction-int-02',
    ),
    item(
      'att-05',
      'join_request',
      'Agent "Scribe Example" asks to join',
      age: const Duration(days: 1),
      href: '/ACM/access/join-01',
    ),
    item(
      'att-06',
      'recovery_action',
      'Recover the stalled nightly job',
      agent: 'Engineer Example',
      age: const Duration(hours: 9),
      href: '/ACM/issues/ACM-15',
    ),
    item(
      'att-07',
      'productivity_review',
      'Weekly productivity review is ready',
      age: const Duration(days: 2),
      href: '/ACM/reviews/prod-01',
    ),
    item(
      'att-08',
      'blocker_attention',
      'ACM-21 is blocked on your input',
      agent: 'Tester Example',
      age: const Duration(hours: 7),
      href: '/ACM/issues/ACM-21',
    ),
    item(
      'att-09',
      'review',
      'Review the draft changelog',
      agent: 'Chief Example',
      age: const Duration(hours: 2),
      href: '/ACM/issues/ACM-30',
    ),
    item(
      'att-10',
      'failed_run',
      'Run failed: build step exited with code 1',
      agent: 'Engineer Example',
      age: const Duration(minutes: 25),
      href: '/ACM/runs/run-01',
    ),
    item(
      'att-11',
      'budget_alert',
      'Budget is at 90% for this month',
      age: const Duration(hours: 6),
      href: '/ACM/costs',
    ),
    item(
      'att-12',
      'agent_error_alert',
      'Tester Example reports an error',
      agent: 'Tester Example',
      age: const Duration(minutes: 5),
    ),
    item(
      'att-13',
      'a_kind_from_a_newer_server',
      'Something this app version does not know',
      age: const Duration(days: 3),
      href: '/ACM/whatever/x-01',
    ),
  ];

  return _feedJson(items, now);
}
