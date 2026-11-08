import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/models/company.dart';

/// The companies the signed-in user can read.
abstract interface class CompanyRepository {
  /// `GET /companies`.
  Future<List<Company>> listCompanies();
}

/// [CompanyRepository] over HTTP.
class HttpCompanyRepository implements CompanyRepository {
  /// Creates the repository.
  const new(this._client);

  final ApiClient _client;

  @override
  Future<List<Company>> listCompanies() async {
    final response = await _client.get('/companies');
    return Company.listFromJson(response.data);
  }
}
