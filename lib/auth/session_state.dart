import 'package:flutter/foundation.dart';

/// Why the user is on the sign-in screen.
enum SignedOutReason {
  /// First start, or nothing stored.
  none,

  /// A call returned 401: the key expired or was revoked (PRD G3).
  expired,

  /// The user signed out.
  userRequested,
}

/// State of the session.
@immutable
sealed class SessionState {
  const new();
}

/// Reading the stored key at start-up.
final class SessionRestoring extends SessionState {
  /// Creates the state.
  const new();
}

/// No usable key. Show the sign-in screen.
final class SignedOut extends SessionState {
  /// Creates the state.
  const new({this.lastBaseUrl, this.reason = SignedOutReason.none});

  /// Address to prefill on the sign-in screen.
  final String? lastBaseUrl;

  /// Why the user is signed out.
  final SignedOutReason reason;
}

/// A key is available (or demo mode is on).
final class SignedIn extends SessionState {
  /// Creates the state for [baseUrl] with the board key [token].
  const new({required this.baseUrl, this.token});

  /// Creates the demo state: fake data, no server, no key.
  const new demo(this.baseUrl) : token = null;

  /// Server address.
  final Uri baseUrl;

  /// Board key. Null in demo mode. Never print this.
  final String? token;

  /// True when the app runs on fake data.
  bool get isDemo => token == null;

  @override
  String toString() => 'SignedIn(${isDemo ? 'demo' : 'key held'})';
}
