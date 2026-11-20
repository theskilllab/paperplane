import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Who created a stored key.
///
/// A [minted] key was requested by Paperplane (email sign-in or device login)
/// and belongs to this app, so a rotation may revoke it. A [pasted] key was
/// typed in by the user and may be in use by another client, so rotation must
/// leave it live. An install from before this record existed has unknown
/// provenance, which is treated as [pasted] for that safety reason.
enum KeyOrigin {
  /// Paperplane asked the server for this key.
  minted,

  /// The user pasted this key in; it may be used elsewhere.
  pasted,
}

/// A board key as stored on the device: the secret plus the metadata the app
/// needs to rotate it later.
///
/// The whole record is one secure-storage value, so a rotation is a single
/// write. A failed write leaves the old key in place. The token is a
/// credential: this type never prints it.
@immutable
class StoredKey {
  /// Creates a stored key.
  const new({
    required this.token,
    required this.createdAt,
    this.keyId,
    this.expiresAt,
    this.origin = KeyOrigin.minted,
    this.legacy = false,
  });

  /// Reads a stored value.
  ///
  /// A value from before rotation metadata existed is a bare token. Its age is
  /// unknown, so it gets [now] as its start and [legacy] set, and the caller
  /// rewrites it once. A value that looks like our JSON but cannot be read
  /// becomes [StoredKey.invalid], which the caller treats as no key rather
  /// than guessing at a credential.
  factory decode(String raw, {required DateTime now}) {
    if (!raw.startsWith('{')) {
      // Unknown provenance: do not let a rotation revoke a key that the user
      // may still use in another client.
      return StoredKey(
        token: raw,
        createdAt: now,
        origin: KeyOrigin.pasted,
        legacy: true,
      );
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return StoredKey.invalid();
      final token = json['token'];
      if (token is! String || token.isEmpty) return StoredKey.invalid();
      final keyId = json['keyId'];
      final createdAt = json['createdAt'];
      final expiresAt = json['expiresAt'];
      return StoredKey(
        token: token,
        keyId: keyId is String && keyId.isNotEmpty ? keyId : null,
        createdAt:
            (createdAt is String ? DateTime.tryParse(createdAt) : null) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt) : null,
        origin: json['origin'] == KeyOrigin.pasted.name
            ? KeyOrigin.pasted
            : KeyOrigin.minted,
      );
    } on FormatException {
      return StoredKey.invalid();
    }
  }

  /// A record that cannot be used. Never a real key.
  factory invalid() =>
      StoredKey(token: '', createdAt: DateTime.fromMillisecondsSinceEpoch(0));

  /// The secret. Never log, print or put this in preferences.
  final String token;

  /// Server id, used to revoke the old key after a rotation.
  final String? keyId;

  /// When the app stored this key. Rotation counts from here.
  final DateTime createdAt;

  /// When the server says the key expires, when known.
  final DateTime? expiresAt;

  /// Who created this key. A rotation revokes only [KeyOrigin.minted] keys.
  final KeyOrigin origin;

  /// True for a bare token from an install that predates rotation metadata.
  final bool legacy;

  /// True when [token] is empty (an unreadable record).
  bool get isUsable => token.isNotEmpty;

  /// True when the key has reached [age] at [now].
  bool ageAtLeast(Duration age, DateTime now) =>
      !now.isBefore(createdAt.add(age));

  /// True when the server expiry has passed at [now].
  bool isExpiredAt(DateTime now) {
    final expiry = expiresAt;
    return expiry != null && !now.isBefore(expiry);
  }

  /// The secure-storage form. Compact, one value, no secrets in the clear
  /// beyond the token that the entry already held.
  String encode() => jsonEncode({
    'token': token,
    if (keyId != null) 'keyId': keyId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    'origin': origin.name,
  });

  @override
  String toString() =>
      'StoredKey(${keyId == null ? 'no id' : 'id present'}, '
      'created ${createdAt.toIso8601String()})';
}
