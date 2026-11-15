import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/models/agent.dart';

/// Agents of a company. Used by the Inbox (who asked), S6 (names, the
/// @agent picker) and S7 (assignee).
abstract interface class AgentRepository {
  /// `GET /companies/{id}/agents`, in the server's order.
  Future<List<Agent>> listAgents(String companyId);
}

/// [AgentRepository] over HTTP.
class HttpAgentRepository implements AgentRepository {
  /// Creates the repository.
  const new(this._client);

  final ApiClient _client;

  @override
  Future<List<Agent>> listAgents(String companyId) async {
    final response = await _client.get(
      '/companies/$companyId/agents',
      scope: companyId,
    );
    return Agent.listFromJson(response.data);
  }
}

/// Agent id to display name, the shape the Inbox rows need.
Map<String, String> agentNameMap(Iterable<Agent> agents) => {
  for (final agent in agents) agent.id: agent.name,
};
