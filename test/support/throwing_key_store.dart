import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/stored_key.dart';

/// [KeyStore] that can fail any operation, for start-up, rotation and sign-out
/// tests.
class ThrowingKeyStore implements KeyStore {
  /// Creates a store holding [values]. Failures are off until a flag is set.
  new({Map<String, StoredKey> values = const {}}) : _values = Map.of(values);

  final Map<String, StoredKey> _values;
  final Map<String, Set<String>> _signedOut = {};

  /// When true, [readAll] throws.
  bool failReadAll = false;

  /// When true, [read] throws.
  bool failRead = false;

  /// When true, [delete] throws.
  bool failDelete = false;

  /// When true, [markSignOutPending] throws, so the intent cannot be recorded.
  bool failMarkSignedOut = false;

  /// When true, [markSignOutPending] stores the token and then throws. Models
  /// a platform that commits before reporting an error.
  bool throwAfterMarkSignedOut = false;

  /// When true, [signOutPendingSessions] throws.
  bool failReadSignedOut = false;

  /// When true, [clearSignOutPending] throws.
  bool failClearSignedOut = false;

  /// When true, [write] throws.
  bool failWrite = false;

  /// When true, [write] stores the value and then throws. Models a platform
  /// that commits before reporting an error.
  bool throwAfterWrite = false;

  /// When true, a failed [write] also makes later reads fail, so the app
  /// cannot reconcile what the entry holds.
  bool failReadAfterWriteError = false;

  @override
  Future<StoredKey?> read(String instanceKey) async {
    if (failRead) throw StateError('keystore read failed');
    return _values[instanceKey];
  }

  @override
  Future<void> write(String instanceKey, StoredKey key) async {
    if (failWrite) {
      if (failReadAfterWriteError) failRead = true;
      throw StateError('keystore write failed');
    }
    _values[instanceKey] = key;
    if (throwAfterWrite) throw StateError('keystore write reported error');
  }

  @override
  Future<void> delete(String instanceKey) async {
    if (failDelete) throw StateError('keystore delete failed');
    _values.remove(instanceKey);
  }

  @override
  Future<Map<String, StoredKey>> readAll() async {
    if (failReadAll) throw StateError('keystore readAll failed');
    return Map.of(_values);
  }

  @override
  Future<void> markSignOutPending(
    String instanceKey,
    Set<String> tokens,
  ) async {
    if (failMarkSignedOut) {
      throw StateError('keystore sign-out marker failed');
    }
    _signedOut[instanceKey] = Set.of(tokens);
    if (throwAfterMarkSignedOut) {
      throw StateError('keystore sign-out marker reported error');
    }
  }

  @override
  Future<Set<String>> signOutPendingSessions(String instanceKey) async {
    if (failReadSignedOut) {
      throw StateError('keystore sign-out marker read failed');
    }
    return Set.of(_signedOut[instanceKey] ?? const <String>{});
  }

  @override
  Future<void> clearSignOutPending(String instanceKey) async {
    if (failClearSignedOut) {
      throw StateError('keystore sign-out marker clear failed');
    }
    _signedOut.remove(instanceKey);
  }
}
