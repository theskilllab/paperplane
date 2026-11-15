import 'dart:convert';

import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/auth/app_prefs.dart';

/// The companies the signed-in user can read.
abstract interface class CompanyRepository {
  /// `GET /companies`.
  Future<List<Company>> listCompanies();

  /// The last list kept on this device, or null. Used on a cold start without
  /// network so the Inbox can still name the active company.
  List<Company>? cachedCompanies();
}

/// [CompanyRepository] over HTTP.
class HttpCompanyRepository implements CompanyRepository {
  /// Creates the repository.
  const new(this._client, {this.prefs});

  final ApiClient _client;

  /// Cache for a cold start without network. Null in tests.
  final AppPrefs? prefs;

  @override
  Future<List<Company>> listCompanies() async {
    final generation = prefs?.cacheGeneration;
    final response = await _client.get('/companies');
    final companies = Company.listFromJson(response.data);
    await prefs?.setCachedCompaniesJson(
      jsonEncode(response.data),
      expectedGeneration: generation,
    );
    return companies;
  }

  @override
  List<Company>? cachedCompanies() {
    final raw = prefs?.cachedCompaniesJson;
    if (raw == null) return null;
    try {
      final companies = Company.listFromJson(jsonDecode(raw));
      return companies.isEmpty ? null : companies;
    } on FormatException {
      return null;
    }
  }
}
