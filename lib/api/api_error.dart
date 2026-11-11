/// Typed failure of a call to the Paperclip server.
///
/// One sealed hierarchy so every screen handles failures the same way. Map it
/// to UI copy with `presentationFor` in `lib/core/error_presentation.dart`.
sealed class ApiError implements Exception {
  const new();
}

/// The device has no network or the host cannot be reached (DNS, refused).
final class Offline extends ApiError {
  /// Creates the error.
  const new();

  @override
  String toString() => 'Offline';
}

/// The server did not answer within the timeout.
final class TimedOut extends ApiError {
  /// Creates the error.
  const new();

  @override
  String toString() => 'TimedOut';
}

/// The TLS handshake or certificate check failed.
final class Tls extends ApiError {
  /// Creates the error.
  const new();

  @override
  String toString() => 'Tls';
}

/// The server refuses the hostname the app used (private-exposure instances
/// answer 403 to any host that is not on their allow-list).
final class HostNotAllowed extends ApiError {
  /// Creates the error.
  const new();

  @override
  String toString() => 'HostNotAllowed';
}

/// 401. The board key is missing, expired or revoked.
final class Unauthorized extends ApiError {
  /// Creates the error.
  const new();

  @override
  String toString() => 'Unauthorized';
}

/// 403 that is not [HostNotAllowed].
final class Forbidden extends ApiError {
  /// Creates the error with the server's [message] (may be empty).
  const new(this.message);

  /// Server text. Only show it for write calls (PRD G4).
  final String message;

  @override
  String toString() => 'Forbidden';
}

/// 404.
final class NotFound extends ApiError {
  /// Creates the error.
  const new();

  @override
  String toString() => 'NotFound';
}

/// 409 or 422 from a call made with `stateConflict: true` (a decision call).
///
/// The item changed on the server. The caller re-fetches it and shows
/// "Already handled" (PRD G10). Never match on the server message.
final class AlreadyHandled extends ApiError {
  /// Creates the error for the HTTP [status] (409 or 422).
  const new(this.status);

  /// HTTP status that produced it.
  final int status;

  @override
  String toString() => 'AlreadyHandled($status)';
}

/// Any 3xx (except 304). The client never follows redirects, so the board
/// key is not sent to a URL the user did not enter. Usually the server URL
/// should use `https://`.
final class Redirected extends ApiError {
  /// Creates the error.
  const new();

  @override
  String toString() => 'Redirected';
}

/// 429.
final class RateLimited extends ApiError {
  /// Creates the error. [retryAfter] is null when the header is missing.
  const new(this.retryAfter);

  /// How long the server asked the client to wait.
  final Duration? retryAfter;

  @override
  String toString() => 'RateLimited';
}

/// Any other non-success status (5xx, and 4xx the app does not special-case).
final class Server extends ApiError {
  /// Creates the error for the HTTP [status].
  const new(this.status);

  /// HTTP status code. Safe to show; the body is not kept.
  final int status;

  @override
  String toString() => 'Server($status)';
}

/// A failure that fits none of the above (bad JSON shape, cancelled, bug).
final class Unexpected extends ApiError {
  /// Creates the error. [detail] must not contain secrets.
  const new([this.detail]);

  /// Short, non-sensitive hint for logs and the error screen.
  final String? detail;

  @override
  String toString() => 'Unexpected';
}
