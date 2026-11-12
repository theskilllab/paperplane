import 'package:shared_preferences/shared_preferences.dart';

/// Small, non-secret preferences: the last server address and company.
///
/// Credentials never go here (see `KeyStore`).
class AppPrefs {
  /// Creates the wrapper around [_prefs].
  const new(this._prefs);

  final SharedPreferences _prefs;

  static const _lastBaseUrl = 'last_base_url';
  static const _lastCompanyId = 'last_company_id';
  static const _cachedCompanies = 'cached_companies';
  static const _cachedFeed = 'cached_feed';
  static const _cachedFeedCompany = 'cached_feed_company';
  static const _cachedFeedAt = 'cached_feed_at';

  /// Server address used last, to prefill the sign-in form.
  String? get lastBaseUrl => _prefs.getString(_lastBaseUrl);

  /// Remembers [value] as the last server address.
  Future<void> setLastBaseUrl(String value) =>
      _prefs.setString(_lastBaseUrl, value);

  /// Company shown last.
  String? get lastCompanyId => _prefs.getString(_lastCompanyId);

  /// Remembers [value] as the last company, or forgets it when null.
  Future<void> setLastCompanyId(String? value) => value == null
      ? _prefs.remove(_lastCompanyId)
      : _prefs.setString(_lastCompanyId, value);

  /// Raw JSON of the last `GET /companies` answer, for a cold start without
  /// network (PRD S1 AC11).
  String? get cachedCompaniesJson => _prefs.getString(_cachedCompanies);

  /// Remembers [json] as the company list.
  Future<void> setCachedCompaniesJson(String json) =>
      _prefs.setString(_cachedCompanies, json);

  /// Raw JSON of the last attention feed of [cachedFeedCompanyId].
  String? get cachedFeedJson => _prefs.getString(_cachedFeed);

  /// Company the cached feed belongs to.
  String? get cachedFeedCompanyId => _prefs.getString(_cachedFeedCompany);

  /// When the cached feed was fetched.
  DateTime? get cachedFeedAt {
    final ms = _prefs.getInt(_cachedFeedAt);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  /// Remembers [json] as the feed of [companyId], fetched at [at].
  Future<void> setCachedFeed({
    required String companyId,
    required String json,
    required DateTime at,
  }) async {
    await _prefs.setString(_cachedFeed, json);
    await _prefs.setString(_cachedFeedCompany, companyId);
    await _prefs.setInt(_cachedFeedAt, at.toUtc().millisecondsSinceEpoch);
  }

  /// Forgets the cached feed. Called when the user switches company, so the
  /// old company's rows cannot appear under the new one (S3 AC3).
  Future<void> clearCachedFeed() async {
    await _prefs.remove(_cachedFeed);
    await _prefs.remove(_cachedFeedCompany);
    await _prefs.remove(_cachedFeedAt);
  }

  /// Forgets every cached server answer. Called on sign-out and on 401 so no
  /// data from the old session can appear for the next one (PRD G3).
  Future<void> clearCachedData() async {
    await _prefs.remove(_cachedCompanies);
    await clearCachedFeed();
  }
}
