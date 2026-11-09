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
}
