import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/auth/stored_key.dart';

void main() {
  final now = DateTime.utc(2026, 11, 20, 12);

  test('round trips the token, id and dates', () {
    final original = StoredKey(
      token: 'pcp_board_fake',
      keyId: 'key-1',
      createdAt: now,
      expiresAt: now.add(const Duration(days: 30)),
    );
    final decoded = StoredKey.decode(original.encode(), now: now);

    expect(decoded.token, original.token);
    expect(decoded.keyId, original.keyId);
    expect(decoded.createdAt, original.createdAt);
    expect(decoded.expiresAt, original.expiresAt);
    expect(decoded.origin, KeyOrigin.minted);
    expect(decoded.legacy, isFalse);
  });

  test('round trips a pasted key origin', () {
    final original = StoredKey(
      token: 'pcp_board_fake',
      createdAt: now,
      origin: KeyOrigin.pasted,
    );
    final decoded = StoredKey.decode(original.encode(), now: now);
    expect(decoded.origin, KeyOrigin.pasted);
  });

  test('a record without an origin is treated as pasted', () {
    final raw =
        '{"token":"pcp_board_fake","createdAt":"${now.toIso8601String()}"}';
    // A record from an earlier app revision may hold a pasted key, so it must
    // never be revoked automatically.
    expect(StoredKey.decode(raw, now: now).origin, KeyOrigin.pasted);
  });

  test('a record with an unknown origin is treated as pasted', () {
    final raw =
        '{"token":"pcp_board_fake","createdAt":"${now.toIso8601String()}",'
        '"origin":"something-else"}';
    expect(StoredKey.decode(raw, now: now).origin, KeyOrigin.pasted);
  });

  test('a bare token is legacy, unowned, and starts its age at now', () {
    final decoded = StoredKey.decode('pcp_board_fake', now: now);
    expect(decoded.token, 'pcp_board_fake');
    expect(decoded.createdAt, now);
    expect(decoded.legacy, isTrue);
    // Unknown provenance must not be revoked automatically on rotation.
    expect(decoded.origin, KeyOrigin.pasted);
  });

  test('unreadable JSON is unusable, not a guessed token', () {
    expect(StoredKey.decode('{"token":', now: now).isUsable, isFalse);
    expect(StoredKey.decode('{}', now: now).isUsable, isFalse);
    expect(StoredKey.decode('{"token":""}', now: now).isUsable, isFalse);
  });

  test('age and expiry are inclusive at the boundary', () {
    final key = StoredKey(
      token: 'k',
      createdAt: now.subtract(const Duration(days: 7)),
      expiresAt: now,
    );
    expect(key.ageAtLeast(const Duration(days: 7), now), isTrue);
    expect(key.isExpiredAt(now), isTrue);
    expect(key.isExpiredAt(now.subtract(const Duration(seconds: 1))), isFalse);
  });

  test('never prints the token (G7)', () {
    final key = StoredKey(
      token: 'pcp_board_super_secret',
      keyId: 'key-1',
      createdAt: now,
    );
    expect('$key', isNot(contains('pcp_board')));
    expect('$key', isNot(contains('super_secret')));
  });
}
