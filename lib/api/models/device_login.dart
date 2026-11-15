import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// State of a device-login challenge, as the poll endpoint reports it.
enum DeviceLoginStatus {
  /// The user has not approved the request yet.
  pending,

  /// The user approved it. The token from challenge creation is now live.
  approved,

  /// The user denied it.
  denied,

  /// The challenge expired before approval.
  expired,

  /// A status this app version does not know.
  unknown;

  /// Parses the wire value tolerantly.
  static DeviceLoginStatus parse(String? value) => switch (value) {
    'pending' => pending,
    'approved' => approved,
    'denied' => denied,
    'expired' => expired,
    _ => unknown,
  };
}

/// A device-login challenge (`POST /cli-auth/challenges`).
///
/// The app opens the approval page in the system browser and polls `pollPath`.
/// The board key is [boardApiToken] from the create answer: it is inert until
/// approval, but the approved poll answer does not repeat it (THE-203 A2).
@immutable
class DeviceChallenge {
  /// Creates the challenge.
  const new({
    required this.id,
    required this.token,
    required this.boardApiToken,
    required this.pollPath,
    this.approvalPath,
    this.approvalUrl,
    this.expiresAt,
    this.pollInterval = const Duration(seconds: 3),
  });

  /// Parses the create answer tolerantly.
  factory fromJson(Map<String, Object?> json) {
    final intervalMs = readInt(
      json,
      'suggestedPollIntervalMs',
      fallback: 3000,
    ).clamp(1000, 10000);
    return DeviceChallenge(
      id: readString(json, 'id') ?? '',
      token: readString(json, 'token') ?? '',
      boardApiToken: readString(json, 'boardApiToken') ?? '',
      pollPath: readString(json, 'pollPath') ?? '',
      approvalPath: readNonEmpty(json, 'approvalPath'),
      approvalUrl: readNonEmpty(json, 'approvalUrl'),
      expiresAt: readDate(json, 'expiresAt'),
      pollInterval: Duration(milliseconds: intervalMs),
    );
  }

  /// Challenge id.
  final String id;

  /// Challenge secret, sent as the `token` query of the poll.
  final String token;

  /// Board key that becomes active after approval.
  final String boardApiToken;

  /// Server path of the poll endpoint, for example
  /// `/cli-auth/challenges/<id>` (no `/api` prefix).
  final String pollPath;

  /// Server path of the approval page.
  final String? approvalPath;

  /// Absolute approval URL, when the server sent one.
  final String? approvalUrl;

  /// When the challenge stops being valid.
  final DateTime? expiresAt;

  /// Poll interval the server suggests, clamped to a safe range.
  final Duration pollInterval;

  /// True when the answer has the fields the app needs.
  bool get isUsable =>
      id.isNotEmpty &&
      token.isNotEmpty &&
      boardApiToken.isNotEmpty &&
      pollPath.isNotEmpty;
}
