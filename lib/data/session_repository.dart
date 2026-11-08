import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/models/health.dart';
import 'package:paperplane/api/models/session_info.dart';

/// Server-side session facts. Sign-in itself (cookie session, then
/// `POST /board-api-keys`) arrives with PR 1b and extends this interface.
abstract interface class SessionRepository {
  /// `GET /health` (no auth). Tells whether this is a supported Paperclip.
  Future<HealthInfo> health();

  /// `GET /cli-auth/me`. Verifies the key and tells who owns it.
  Future<SessionInfo> me();

  /// `POST /cli-auth/revoke-current`. Invalidates the key in use.
  Future<void> revokeCurrentKey();
}

/// [SessionRepository] over HTTP.
class HttpSessionRepository implements SessionRepository {
  /// Creates the repository.
  const new(this._client);

  final ApiClient _client;

  @override
  Future<HealthInfo> health() async {
    final response = await _client.get('/health');
    return HealthInfo.fromJson(_map(response.data));
  }

  @override
  Future<SessionInfo> me() async {
    final response = await _client.get('/cli-auth/me');
    return SessionInfo.fromJson(_map(response.data));
  }

  @override
  Future<void> revokeCurrentKey() async {
    await _client.post('/cli-auth/revoke-current');
  }

  static Map<String, Object?> _map(Object? data) =>
      data is Map ? data.cast<String, Object?>() : const {};
}
