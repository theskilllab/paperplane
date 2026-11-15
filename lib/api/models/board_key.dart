import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// A freshly minted board key (`POST /board-api-keys`).
///
/// The server shows `token` only once. It is handed to the `KeyStore` and
/// never logged or put in preferences.
@immutable
class BoardKey {
  /// Creates the key.
  const new({required this.token, this.id, this.name, this.expiresAt});

  /// Parses the answer tolerantly.
  factory fromJson(Map<String, Object?> json) => BoardKey(
    token: readString(json, 'token') ?? '',
    id: readNonEmpty(json, 'id'),
    name: readNonEmpty(json, 'name'),
    expiresAt: readDate(json, 'expiresAt'),
  );

  /// The secret. Empty when the server sent no token.
  final String token;

  /// Server id, used to revoke or rotate the key later.
  final String? id;

  /// Name shown in the server's key list, for example `Paperplane (iPhone)`.
  final String? name;

  /// Expiry. The app asks for 30 days and never asks for "never".
  final DateTime? expiresAt;

  @override
  String toString() => 'BoardKey(id: $id, expiresAt: $expiresAt)';
}
