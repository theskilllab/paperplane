import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/models/agent.dart';
import 'package:paperplane/data/agent_repository.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/data/inbox_repository.dart';
import 'package:paperplane/data/project_repository.dart';

import '../support/fake_adapter.dart';
import '../support/fixtures.dart';

ApiClient clientFor(FakeAdapter adapter) => ApiClient(
  baseUrl: Uri.parse('https://paperclip.example.test'),
  adapter: adapter,
);

void main() {
  group('AgentRepository', () {
    test('parses role and finds the CEO', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('agents.json')),
      );
      final agents = await HttpAgentRepository(clientFor(adapter))
          .listAgents('c1');

      expect(adapter.requests.single.path, '/companies/c1/agents');
      expect(agents.map((a) => a.role), ['ceo', 'engineer', 'qa', 'general']);
      expect(Agent.ceoOf(agents)?.id, 'agent-ceo');
    });

    test('no CEO means no default', () {
      expect(
        Agent.ceoOf(const [Agent(id: 'a', name: 'A', role: 'engineer')]),
        isNull,
      );
      expect(Agent.ceoOf(const []), isNull);
    });

    test('a terminated CEO is not the default', () {
      expect(
        Agent.ceoOf(const [
          Agent(id: 'a', name: 'A', role: 'ceo', status: 'terminated'),
        ]),
        isNull,
      );
    });

    test('tolerates odd entries', () {
      final agents = Agent.listFromJson([
        {'id': 'a1'},
        {'name': 'no id'},
        'junk',
        null,
      ]);
      expect(agents.single.id, 'a1');
      expect(agents.single.name, '');
      expect(agents.single.role, '');
    });

    test(
      'InboxRepository.agentNames delegates to the agent repository',
      () async {
        final agents = FakeAgentRepository();
        final adapter = FakeAdapter((o) async => throw StateError('no http'));
        final names = await HttpInboxRepository(
          clientFor(adapter),
          agents: agents,
        ).agentNames('c1');

        expect(agents.calls, 1);
        expect(names['agent-ceo'], 'Chief Example');
        expect(adapter.requests, isEmpty);
      },
    );
  });

  group('ProjectRepository', () {
    test('drops archived projects', () async {
      final adapter = FakeAdapter(
        (o) async => jsonBody(loadFixture('projects.json')),
      );
      final projects = await HttpProjectRepository(clientFor(adapter))
          .listProjects('c1');

      expect(adapter.requests.single.path, '/companies/c1/projects');
      expect(projects.map((p) => p.name), ['Website', 'Docs']);
    });

    test('fake serves demo projects', () async {
      final projects = await FakeProjectRepository().listProjects('c1');
      expect(projects, hasLength(2));
    });
  });
}
