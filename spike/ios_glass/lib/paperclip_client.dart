// Throwaway THE-203 spike client. It keeps cookies and keys in memory only.
import 'dart:convert';
import 'dart:io';

class ApiResponse {
  ApiResponse({
    required this.status,
    required this.body,
    required this.headers,
  });

  final int status;
  final String body;
  final Map<String, String> headers;

  Map<String, dynamic>? get json {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  int? get retryAfter {
    final raw = headers['retry-after'] ?? headers['x-retry-after'];
    return raw == null ? null : int.tryParse(raw.trim());
  }

  String get summary {
    final data = json;
    if (data != null) {
      for (final key in const ['message', 'error', 'code']) {
        final value = data[key];
        if (value is String && value.isNotEmpty) return value;
      }
    }
    if (body.isEmpty) return '<empty>';
    return body.length > 160 ? '${body.substring(0, 160)}...' : body;
  }
}

class PaperclipClient {
  PaperclipClient({required String baseUrl})
    : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '') {
    _http.connectionTimeout = const Duration(seconds: 15);
  }

  final String baseUrl;
  final HttpClient _http = HttpClient();
  final Map<String, String> _cookies = {};

  String get origin {
    final uri = Uri.parse(baseUrl);
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static String apiPath(String path) =>
      path.startsWith('/api') ? path : '/api$path';

  static String redactKey(String? key) {
    if (key == null || key.isEmpty) return '<none>';
    final prefix = key.length >= 10 ? key.substring(0, 10) : key;
    return '$prefix... (len=${key.length})';
  }

  Future<ApiResponse> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
    bool useCookies = true,
  }) async {
    final request = await _http.openUrl(method, Uri.parse('$baseUrl$path'));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (useCookies && _cookies.isNotEmpty) {
      request.headers.set(
        HttpHeaders.cookieHeader,
        _cookies.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; '),
      );
    }
    headers?.forEach((name, value) => request.headers.set(name, value));
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    for (final cookie in response.cookies) {
      _cookies[cookie.name] = cookie.value;
    }
    final text = await utf8.decoder.bind(response).join();
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = values.join(', ');
    });
    return ApiResponse(
      status: response.statusCode,
      body: text,
      headers: responseHeaders,
    );
  }

  Future<ApiResponse> signIn({
    required String email,
    required String password,
  }) {
    return _send(
      'POST',
      '/api/auth/sign-in/email',
      headers: {'origin': origin},
      body: {'email': email, 'password': password},
    );
  }

  Future<ApiResponse> mintBoardKey({required String name}) {
    return _send(
      'POST',
      '/api/board-api-keys',
      headers: {'origin': origin},
      body: {'name': name},
    );
  }

  Future<ApiResponse> signOut() {
    return _send('POST', '/api/auth/sign-out', headers: {'origin': origin});
  }

  Future<ApiResponse> me(String token) {
    return _send(
      'GET',
      '/api/cli-auth/me',
      headers: {'authorization': 'Bearer $token'},
      useCookies: false,
    );
  }

  Future<ApiResponse> health({String? token}) {
    return _send(
      'GET',
      '/api/health',
      headers: token == null ? null : {'authorization': 'Bearer $token'},
      useCookies: false,
    );
  }

  Future<ApiResponse> createChallenge() {
    return _send(
      'POST',
      '/api/cli-auth/challenges',
      body: {'command': 'paperplane', 'clientName': 'Paperplane iOS spike'},
      useCookies: false,
    );
  }

  Future<ApiResponse> pollDevice({
    required String pollPath,
    required String token,
  }) {
    final query = Uri(queryParameters: {'token': token}).query;
    return _send('GET', '${apiPath(pollPath)}?$query', useCookies: false);
  }

  void close() => _http.close(force: true);
}
