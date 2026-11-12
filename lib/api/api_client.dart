import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/json.dart';
import 'package:paperplane/api/redactor.dart';

/// Successful answer of the server.
@immutable
class ApiResponse {
  /// Creates a response.
  const new({
    required this.status,
    this.data,
    this.etag,
    this.notModified = false,
  });

  /// HTTP status.
  final int status;

  /// Decoded JSON body, or null (empty body, or 304).
  final Object? data;

  /// `ETag` header, to send back as `If-None-Match`.
  final String? etag;

  /// True for 304: the caller keeps what it has.
  final bool notModified;
}

/// HTTP client for one Paperclip instance.
///
/// - Adds `Authorization: Bearer <key>` from [tokenProvider] on every call.
/// - Maps every failure to a typed [ApiError]. Nothing else escapes.
/// - Times out after [timeout] (PRD G2: 15 s).
/// - Never logs bodies, hosts or credentials (see [Redactor]).
class ApiClient {
  /// Creates a client for the instance at [baseUrl] (no `/api` suffix).
  new({
    required Uri baseUrl,
    this.tokenProvider,
    this.onUnauthorized,
    this.log,
    this.timeout = const Duration(seconds: 15),
    HttpClientAdapter? adapter,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: '${baseUrl.toString().replaceAll(RegExp(r'/+$'), '')}/api',
           connectTimeout: timeout,
           sendTimeout: timeout,
           receiveTimeout: timeout,
           // A redirect (for example http to https) would resend the board key
           // to another URL. Never follow it; 3xx becomes [Redirected].
           followRedirects: false,
           validateStatus: (status) =>
               status != null &&
               ((status >= 200 && status < 300) || status == 304),
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = tokenProvider?.call();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
            options.extra['hadToken'] = true;
          }
          handler.next(options);
        },
      ),
    );
    if (log != null) _dio.interceptors.add(_LogInterceptor(log!));
  }

  /// A client for the signed-out state: every call fails with
  /// [Unauthorized] without touching the network. Lets repositories exist
  /// while the router is still moving to S1.
  factory signedOut() => ApiClient(
    baseUrl: Uri.parse('https://signed-out.invalid'),
    adapter: _SignedOutAdapter(),
  );

  final Dio _dio;

  /// Returns the current board key, or null when signed out.
  final String? Function()? tokenProvider;

  /// Called once when a call that carried a key gets 401 (PRD G3).
  final void Function()? onUnauthorized;

  /// Sink for redacted log lines. Null disables logging.
  final void Function(String line)? log;

  /// Per-request timeout.
  final Duration timeout;

  final Map<String, CancelToken> _scopes = {};

  /// Cancels every in-flight call made with the same [scope], for example a
  /// company id when the user switches company.
  void cancelScope(String scope) {
    _scopes.remove(scope)?.cancel('scope cancelled');
  }

  /// Cancels all in-flight calls and releases the connection pool.
  void close() {
    for (final token in _scopes.values) {
      token.cancel('client closed');
    }
    _scopes.clear();
    _dio.close(force: true);
  }

  /// `GET [path]` (relative to `/api`, starting with `/`).
  ///
  /// Pass [ifNoneMatch] to get a 304 ([ApiResponse.notModified]) when nothing
  /// changed.
  Future<ApiResponse> get(
    String path, {
    Map<String, Object?>? query,
    String? ifNoneMatch,
    String? scope,
  }) => _send(
    'GET',
    path,
    query: query,
    headers: {'If-None-Match': ?ifNoneMatch},
    scope: scope,
  );

  /// `POST [path]` with a JSON [body].
  ///
  /// Set [stateConflict] for decision calls (approve, reject, respond): 409
  /// and 422 then become [AlreadyHandled]. For other writes they are plain
  /// [Server] errors, so a validation failure is not shown as "already
  /// handled".
  Future<ApiResponse> post(
    String path, {
    Object? body,
    bool stateConflict = false,
    String? scope,
  }) => _send(
    'POST',
    path,
    body: body,
    stateConflict: stateConflict,
    scope: scope,
  );

  /// `DELETE [path]`.
  Future<ApiResponse> delete(String path, {String? scope}) =>
      _send('DELETE', path, scope: scope);

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? headers,
    Object? body,
    bool stateConflict = false,
    String? scope,
  }) async {
    final cancelToken = scope == null
        ? null
        : _scopes.putIfAbsent(scope, CancelToken.new);
    try {
      final response = await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(method: method, headers: headers),
      );
      return ApiResponse(
        status: response.statusCode ?? 200,
        data: response.data,
        etag: response.headers.value('etag'),
        notModified: response.statusCode == 304,
      );
    } on DioException catch (e) {
      final error = mapDioException(e, stateConflict: stateConflict);
      if (error is Unauthorized && e.requestOptions.extra['hadToken'] == true) {
        onUnauthorized?.call();
      }
      throw error;
    } on ApiError {
      rethrow;
    } on Object {
      throw const Unexpected();
    }
  }

  /// Maps a Dio failure to an [ApiError]. Public for tests.
  @visibleForTesting
  static ApiError mapDioException(
    DioException e, {
    bool stateConflict = false,
  }) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimedOut();
      case DioExceptionType.badCertificate:
        return const Tls();
      case DioExceptionType.cancel:
        return const Unexpected('cancelled');
      case DioExceptionType.transformTimeout:
        return const Unexpected('transform timeout');
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        final cause = e.error;
        if (cause is TlsException) return const Tls();
        if (cause is SocketException) return const Offline();
        if (cause is TimeoutException) return const TimedOut();
        return e.type == DioExceptionType.connectionError
            ? const Offline()
            : const Unexpected();
      case DioExceptionType.badResponse:
        return _fromStatus(
          e.response?.statusCode ?? 0,
          e.response,
          stateConflict: stateConflict,
        );
    }
  }

  static ApiError _fromStatus(
    int status,
    Response<Object?>? response, {
    required bool stateConflict,
  }) {
    switch (status) {
      case 401:
        return const Unauthorized();
      case 403:
        final message = _serverMessage(response?.data);
        // The only signal the server gives for an unlisted hostname is its
        // text. Do this one match here and nowhere else.
        if (message.toLowerCase().contains('hostname is not allowed')) {
          return const HostNotAllowed();
        }
        return Forbidden(message);
      case 404:
        return const NotFound();
      case >= 300 && < 400:
        return const Redirected();
      case 409 || 422:
        return stateConflict ? AlreadyHandled(status) : Server(status);
      case 429:
        final seconds = int.tryParse(
          response?.headers.value('retry-after') ?? '',
        );
        return RateLimited(seconds == null ? null : Duration(seconds: seconds));
      default:
        return Server(status);
    }
  }

  static String _serverMessage(Object? data) {
    final map = asMap(data);
    final error = map['error'];
    final text = error is String
        ? error
        : readString(asMap(error), 'message') ?? readString(map, 'message');
    return text ?? '';
  }
}

class _LogInterceptor extends Interceptor {
  new(this._log);

  final void Function(String line) _log;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['startedAt'] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    _line(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _line(err.requestOptions, err.response?.statusCode, error: err.type.name);
    handler.next(err);
  }

  // Path only: no host (a private URL), no query, no body, no credentials.
  void _line(RequestOptions options, int? status, {String? error}) {
    final started = options.extra['startedAt'];
    final ms = started is int
        ? DateTime.now().millisecondsSinceEpoch - started
        : null;
    final headers = Redactor.redactHeaders(options.headers);
    _log(
      Redactor.redact(
        '${options.method} ${options.path} '
        '-> ${status ?? error ?? '?'}'
        '${ms == null ? '' : ' (${ms}ms)'} '
        'headers=$headers',
      ),
    );
  }
}

class _SignedOutAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('{}', 401);

  @override
  void close({bool force = false}) {}
}
