import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// Answer of `GET /cli-auth/me`: who the current board key belongs to.
@immutable
class SessionInfo {
  /// Creates the value.
  const new({
    required this.userId,
    required this.companyIds,
    this.userName,
    this.userEmail,
    this.keyId,
  });

  /// Parses the body tolerantly.
  factory fromJson(Map<String, Object?> json) {
    final user = asMap(json['user']);
    return SessionInfo(
      userId: readString(user, 'id') ?? '',
      userName: readNonEmpty(user, 'name'),
      userEmail: readNonEmpty(user, 'email'),
      companyIds: [
        for (final id in asList(json['companyIds']))
          if (id is String) id,
      ],
      keyId: readNonEmpty(json, 'keyId'),
    );
  }

  /// User id.
  final String userId;

  /// Display name, when known.
  final String? userName;

  /// Email, when known.
  final String? userEmail;

  /// Companies the key can read.
  final List<String> companyIds;

  /// Id of the board key in use. Needed to rotate or revoke it.
  final String? keyId;
}
