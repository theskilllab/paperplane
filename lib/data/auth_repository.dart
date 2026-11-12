import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/foundation.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/json.dart';
import 'package:paperplane/api/models/board_key.dart';
import 'package:paperplane/api/models/device_login.dart';
import 'package:paperplane/api/models/health.dart';
import 'package:paperplane/api/models/session_info.dart';

/// A signed-in result: the board key to store and the session it belongs to.
@immutable
class AuthSession {
  /// Creates the result.
  const new({required this.token, required this.info});

  /// Board key. Never log or print this.
  final String token;

  /// Who the key belongs to and which companies it can read.
  final SessionInfo info;
}

/// The account has no company, so there is nothing to show (PRD S1 AC5).
class NoCompanyOnAccount implements Exception {
  /// Creates the error.
  const new();

  @override
  String toString() => 'NoCompanyOnAccount';
}

/// Sign-in and device-login calls.
///
/// Separate from the signed-in session repository because these run before a
/// session (and therefore an `ApiClient`) exists.
abstract interface class AuthRepository {
  /// `GET /health` (no auth). Tells whether this is a supported Paperclip.
  Future<HealthInfo> health(Uri baseUrl);

  /// Password-first sign-in (THE-203 A1): browser session cookie, then
  /// `POST /board-api-keys`, then discard the cookie.
  Future<AuthSession> signIn({
    required Uri baseUrl,
    required String email,
    required String password,
    required String keyName,
  });

  /// Verifies a pasted board key with one authenticated call before saving it.
  Future<AuthSession> verifyKey({required Uri baseUrl, required String token});

  /// Creates a device-login challenge (THE-203 A2, the fallback flow).
  Future<DeviceChallenge> startDeviceLogin({
    required Uri baseUrl,
    required String clientName,
  });

  /// Safe approval page for [challenge]: same origin as [baseUrl] only.
  Uri? approvalUri(Uri baseUrl, DeviceChallenge challenge);

  /// Polls a challenge. The caller owns the wait loop and `Retry-After`.
  Future<DeviceLoginStatus> pollDeviceLogin({
    required Uri baseUrl,
    required DeviceChallenge challenge,
  });

  /// Asks the server to end a challenge the user cancelled. Best effort.
  Future<void> cancelDeviceLogin({
    required Uri baseUrl,
    required DeviceChallenge challenge,
  });

  /// Revokes [token] if a later step failed and the key was never saved.
  Future<void> revokeKey({required Uri baseUrl, required String token});
}

/// [AuthRepository] over HTTP.
class HttpAuthRepository implements AuthRepository {
  /// Creates the repository.
  new({
    this.adapter,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 15),
  }) : _now = now ?? DateTime.now;

  /// Replaces Dio's adapter in tests.
  final HttpClientAdapter? adapter;
  final DateTime Function() _now;

  /// Per-request timeout (PRD G2).
  final Duration timeout;

  /// How long a minted key is valid. The app never asks for "never" (THE-203).
  static const keyLifetime = Duration(days: 30);

  ApiClient _client(Uri baseUrl, {String? token}) => ApiClient(
    baseUrl: baseUrl,
    adapter: adapter,
    timeout: timeout,
    tokenProvider: token == null ? null : () => token,
    log: kDebugMode ? debugPrint : null,
  );

  @override
  Future<HealthInfo> health(Uri baseUrl) async {
    final client = _client(baseUrl);
    try {
      final response = await client.get('/health');
      return HealthInfo.fromJson(asMap(response.data));
    } finally {
      client.close();
    }
  }

  @override
  Future<AuthSession> signIn({
    required Uri baseUrl,
    required String email,
    required String password,
    required String keyName,
  }) async {
    final client = _client(baseUrl);
    final origin = baseUrl.origin;
    String? cookie;
    BoardKey? mintedKey;
    try {
      final signedIn = await client.post(
        '/auth/sign-in/email',
        headers: {'Origin': origin},
        body: {'email': email, 'password': password},
      );
      cookie = _cookieHeader(signedIn.headers);
      if (cookie == null) {
        throw const Unexpected('sign-in set no cookie');
      }

      final minted = await client.post(
        '/board-api-keys',
        headers: {'Origin': origin, 'Cookie': cookie},
        body: {
          'name': keyName,
          'expiresAt': _now().toUtc().add(keyLifetime).toIso8601String(),
        },
      );
      final key = BoardKey.fromJson(asMap(minted.data));
      if (key.token.isEmpty) {
        throw const Unexpected('board key had no token');
      }
      mintedKey = key;

      final info = await _me(client, key.token);
      if (info.companyIds.isEmpty) throw const NoCompanyOnAccount();
      return AuthSession(token: key.token, info: info);
    } on Object {
      // Never leave a minted 30-day key live after a later step failed.
      final minted = mintedKey?.token;
      if (minted != null && minted.isNotEmpty) {
        await _revoke(client, minted);
      }
      rethrow;
    } finally {
      // The browser session must not outlive sign-in. A failure here does not
      // undo the board key the user already has.
      if (cookie != null) {
        try {
          await client.post(
            '/auth/sign-out',
            headers: {'Origin': origin, 'Cookie': cookie},
          );
        } on ApiError {
          // Nothing to do: the key is independent of this cookie.
        }
      }
      client.close();
    }
  }

  @override
  Future<AuthSession> verifyKey({
    required Uri baseUrl,
    required String token,
  }) async {
    if (token.isEmpty) throw const Unauthorized();
    final client = _client(baseUrl);
    try {
      final info = await _me(client, token);
      if (info.companyIds.isEmpty) throw const NoCompanyOnAccount();
      return AuthSession(token: token, info: info);
    } finally {
      client.close();
    }
  }

  @override
  Future<DeviceChallenge> startDeviceLogin({
    required Uri baseUrl,
    required String clientName,
  }) async {
    final client = _client(baseUrl);
    try {
      final response = await client.post(
        '/cli-auth/challenges',
        body: {'command': 'paperplane', 'clientName': clientName},
      );
      final challenge = DeviceChallenge.fromJson(asMap(response.data));
      if (!challenge.isUsable || approvalUri(baseUrl, challenge) == null) {
        throw const Unexpected('device challenge was incomplete');
      }
      return challenge;
    } finally {
      client.close();
    }
  }

  @override
  Uri? approvalUri(Uri baseUrl, DeviceChallenge challenge) {
    final path = challenge.approvalPath;
    Uri? candidate;
    if (path != null && path.startsWith('/')) {
      candidate = _joinPath(baseUrl, path);
    } else if (challenge.approvalUrl case final url?) {
      candidate = Uri.tryParse(url);
    }
    if (candidate == null) return null;
    final sameOrigin =
        candidate.scheme == baseUrl.scheme &&
        candidate.host == baseUrl.host &&
        candidate.port == baseUrl.port;
    return sameOrigin ? candidate : null;
  }

  @override
  Future<DeviceLoginStatus> pollDeviceLogin({
    required Uri baseUrl,
    required DeviceChallenge challenge,
  }) async {
    final path = _apiPath(challenge.pollPath);
    if (path == null) throw const Unexpected('bad poll path');
    final client = _client(baseUrl);
    try {
      final response = await client.get(
        path,
        query: {'token': challenge.token},
      );
      final status = DeviceLoginStatus.parse(
        readString(asMap(response.data), 'status'),
      );
      final expiry = challenge.expiresAt;
      if (status == DeviceLoginStatus.pending &&
          expiry != null &&
          !_now().toUtc().isBefore(expiry.toUtc())) {
        return DeviceLoginStatus.expired;
      }
      return status;
    } finally {
      client.close();
    }
  }

  @override
  Future<void> cancelDeviceLogin({
    required Uri baseUrl,
    required DeviceChallenge challenge,
  }) async {
    final path = _apiPath(challenge.pollPath);
    if (path == null) return;
    final client = _client(baseUrl);
    try {
      await client.post('$path/cancel', body: {'token': challenge.token});
    } on ApiError {
      // Cancelling is a courtesy; the challenge expires on its own.
    } finally {
      client.close();
    }
  }

  @override
  Future<void> revokeKey({required Uri baseUrl, required String token}) async {
    if (token.isEmpty) return;
    final client = _client(baseUrl);
    try {
      await _revoke(client, token);
    } finally {
      client.close();
    }
  }

  Future<SessionInfo> _me(ApiClient client, String token) async {
    final response = await client.get(
      '/cli-auth/me',
      headers: {'Authorization': 'Bearer $token'},
    );
    return SessionInfo.fromJson(asMap(response.data));
  }

  Future<void> _revoke(ApiClient client, String token) async {
    try {
      await client.post(
        '/cli-auth/revoke-current',
        headers: {'Authorization': 'Bearer $token'},
        body: const <String, Object?>{},
      );
    } on ApiError {
      // Best effort: the key expires on its own.
    }
  }
}

/// `/api` is in the client base URL; a server-supplied path may include it.
///
/// Returns null for a full URL or `//host` path: the challenge token must not
/// be sent to a host the user did not enter.
String? _apiPath(String path) {
  final parsed = Uri.tryParse(path);
  if (parsed == null || parsed.hasScheme || parsed.hasAuthority) return null;
  final withSlash = parsed.path.startsWith('/')
      ? parsed.path
      : '/${parsed.path}';
  return withSlash.startsWith('/api/') ? withSlash.substring(4) : withSlash;
}

Uri _joinPath(Uri baseUrl, String path) {
  final parsed = Uri.parse(path);
  return Uri(
    scheme: baseUrl.scheme,
    host: baseUrl.host,
    port: baseUrl.hasPort ? baseUrl.port : null,
    path: '${baseUrl.path}${parsed.path}',
    query: parsed.hasQuery ? parsed.query : null,
    fragment: parsed.hasFragment ? parsed.fragment : null,
  );
}

/// Joins every `set-cookie` header into one `Cookie` request header.
///
/// A proxy may join several cookies with ", "; split only where the next
/// token looks like `name=`.
String? _cookieHeader(Map<String, List<String>> headers) {
  final pairs = <String>[];
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() != 'set-cookie') continue;
    for (final raw in entry.value) {
      for (final part in raw.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))) {
        final first = part.split(';').first.trim();
        final eq = first.indexOf('=');
        if (eq > 0) pairs.add(first);
      }
    }
  }
  return pairs.isEmpty ? null : pairs.join('; ');
}
