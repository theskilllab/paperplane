import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Dio adapter that answers from a closure and records every request.
class FakeAdapter implements HttpClientAdapter {
  /// Creates an adapter that calls [handler] for each request.
  new(this.handler);

  /// Produces the answer, or throws a `DioException`.
  final Future<ResponseBody> Function(RequestOptions options) handler;

  /// Requests seen so far.
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    final answer = handler(options);
    if (cancelFuture == null) return answer;
    return Future.any([
      answer,
      cancelFuture.then<ResponseBody>(
        (_) => throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'cancelled',
        ),
      ),
    ]);
  }

  @override
  void close({bool force = false}) {}
}

/// A JSON answer.
ResponseBody jsonBody(
  Object? json, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(json),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

/// An empty answer, for example 304.
ResponseBody emptyBody(
  int status, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString('', status, headers: headers);
