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

/// Builds the demo attention feed body. [now] anchors the timestamps.
Map<String, Object?> demoAttentionJson(DateTime now) {
  String ago(Duration d) => now.subtract(d).toUtc().toIso8601String();
  Map<String, Object?> item(
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
  }) => {
    'id': id,
    'sourceKind': kind,
    'title': title,
    'summary': ?summary,
    'originAgentName': ?agent,
    'createdAt': ago(age),
    'activityAt': ago(age),
    'resolverAudience': audience,
    'inlineResolvable': inlineResolvable,
    'subject': {'href': href, 'metadata': metadata},
  };

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

  final counts = <String, int>{};
  for (final entry in items) {
    final kind = entry['sourceKind']! as String;
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  return {
    'items': items,
    'totalCount': items.length,
    'countsBySourceKind': counts,
    'generatedAt': now.toUtc().toIso8601String(),
    'nextCursor': null,
  };
}
