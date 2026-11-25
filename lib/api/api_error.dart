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

/// A status in the call's `alreadyHandledStatuses` set (a decision call).
///
/// The server uses 409 and 422 for approvals, and only 409 for interactions.
/// The item changed. The caller re-fetches it and shows "Already handled"
/// when the re-read row is no longer pending (PRD G10). Other 409s exist,
/// such as a workspace still syncing, and the server's [message] is shown
/// when the re-read row is still pending.
final class AlreadyHandled extends ApiError {
  /// Creates the error for the HTTP [status] (409 or 422).
  const new(this.status, {this.message = ''});

  /// HTTP status that produced it.
  final int status;

  /// Server text for the conflict, when the server sent one.
  final String message;

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
  ///
  /// [message] is the server's own text for a 4xx validation failure, kept so
  /// a write can show it (PRD G4, S5). A 5xx body is not kept (PRD G5).
  const new(this.status, {this.message = ''});

  /// HTTP status code. Safe to show.
  final int status;

  /// Server text for a 4xx validation failure; empty when there is none.
  final String message;

  @override
  String toString() => 'Server($status)';
}

/// The request was cancelled before it finished (company switch, sign-out,
/// client close). Not a server answer: the UI usually drops it silently.
final class Cancelled extends ApiError {
  /// Creates the error.
  const new();

  @override
  String toString() => 'Cancelled';
}

/// A failure that fits none of the above (bad JSON shape, bug).
final class Unexpected extends ApiError {
  /// Creates the error. [detail] must not contain secrets.
  const new([this.detail]);

  /// Short, non-sensitive hint for logs and the error screen.
  final String? detail;

  @override
  String toString() => 'Unexpected';
}
