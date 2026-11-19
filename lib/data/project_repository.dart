import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/models/project.dart';

/// Projects of a company, for S7's optional project field.
abstract interface class ProjectRepository {
  /// `GET /companies/{id}/projects`, without archived projects.
  Future<List<Project>> listProjects(String companyId);
}

/// [ProjectRepository] over HTTP.
class HttpProjectRepository implements ProjectRepository {
  /// Creates the repository.
  const new(this._client);

  final ApiClient _client;

  @override
  Future<List<Project>> listProjects(String companyId) async {
    final response = await _client.get(
      '/companies/$companyId/projects',
      scope: companyId,
    );
    return [
      for (final project in Project.listFromJson(response.data))
        if (!project.archived) project,
    ];
  }
}
