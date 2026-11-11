import 'package:flutter/foundation.dart';
import 'package:paperplane/api/api_error.dart';

/// How an error looks to the user.
enum ErrorKind {
  /// G2: no network, timeout, or host unreachable.
  offline,

  /// G3: the key is no longer valid.
  sessionExpired,

  /// G4: no access.
  noAccess,

  /// The item does not exist (any more).
  notFound,

  /// G10: someone else decided first.
  alreadyHandled,

  /// The server asked the app to slow down.
  rateLimited,

  /// The admin must allow-list the hostname.
  hostNotAllowed,

  /// Certificate problem.
  tls,

  /// G5: server error or anything unexpected.
  server,
}

/// Copy and behaviour for one [ApiError]. Screens and `AsyncStateView` share
/// this one mapping so every error reads the same everywhere.
@immutable
class ErrorPresentation {
  /// Creates a presentation.
  const new({
    required this.kind,
    required this.title,
    required this.message,
    this.detail,
    this.retryable = true,
  });

  /// Category.
  final ErrorKind kind;

  /// Short headline.
  final String title;

  /// One or two sentences.
  final String message;

  /// Small print, for example `Error 502`. Never a stack trace.
  final String? detail;

  /// Whether a Retry button makes sense.
  final bool retryable;
}

/// Maps [error] to what the user sees.
///
/// [host] is the server name for "Can't reach {host}". [forWrite] switches the
/// 403 copy: a read shows "You don't have access to this" (G4) while a write
/// shows the server's own message when it has one.
ErrorPresentation presentationFor(
  ApiError error, {
  String? host,
  bool forWrite = false,
}) {
  final where = host == null || host.isEmpty ? 'the server' : host;
  return switch (error) {
    Offline() || TimedOut() => ErrorPresentation(
      kind: ErrorKind.offline,
      title: "Can't reach $where",
      message: 'Check your connection or VPN, then try again.',
    ),
    Tls() => ErrorPresentation(
      kind: ErrorKind.tls,
      title: "Can't verify $where",
      message:
          "The server's certificate was not accepted. Use a server with a "
          'valid HTTPS certificate.',
      retryable: false,
    ),
    HostNotAllowed() => const ErrorPresentation(
      kind: ErrorKind.hostNotAllowed,
      title: 'This address is not allowed',
      message:
          'The server only accepts listed hostnames. Ask its admin to allow '
          'this one (paperclipai allowed-hostname), or use an allowed address.',
      retryable: false,
    ),
    Unauthorized() => const ErrorPresentation(
      kind: ErrorKind.sessionExpired,
      title: 'Your session expired',
      message: 'Sign in again.',
      retryable: false,
    ),
    Forbidden(:final message) => ErrorPresentation(
      kind: ErrorKind.noAccess,
      title: forWrite ? "You can't do that" : "You don't have access to this",
      message: forWrite && message.isNotEmpty
          ? message
          : 'Your account is not allowed to see or change this.',
      retryable: false,
    ),
    NotFound() => const ErrorPresentation(
      kind: ErrorKind.notFound,
      title: 'Not found',
      message: 'This item no longer exists.',
      retryable: false,
    ),
    AlreadyHandled() => const ErrorPresentation(
      kind: ErrorKind.alreadyHandled,
      title: 'Already handled',
      message: 'Someone else got there first. Showing the current state.',
      retryable: false,
    ),
    Redirected() => const ErrorPresentation(
      kind: ErrorKind.server,
      title: 'Server redirected the request',
      message: 'Check the server URL and use https://.',
      retryable: false,
    ),
    RateLimited(:final retryAfter) => ErrorPresentation(
      kind: ErrorKind.rateLimited,
      title: 'Too many requests',
      message: retryAfter == null
          ? 'Wait a moment, then try again.'
          : 'Try again in ${retryAfter.inSeconds.clamp(1, 3600)} s.',
    ),
    Server(:final status) => ErrorPresentation(
      kind: ErrorKind.server,
      title: 'Something went wrong',
      message: 'The server could not complete the request.',
      detail: 'Error $status',
    ),
    Unexpected() => const ErrorPresentation(
      kind: ErrorKind.server,
      title: 'Something went wrong',
      message: 'Try again. If it keeps happening, check for an app update.',
    ),
  };
}
