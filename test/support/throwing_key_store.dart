import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/stored_key.dart';

/// [KeyStore] that can fail any operation, for start-up, rotation and sign-out
/// tests.
class ThrowingKeyStore implements KeyStore {
  /// Creates a store holding [values]. Failures are off until a flag is set.
  new({Map<String, StoredKey> values = const {}}) : _values = Map.of(values);

  final Map<String, StoredKey> _values;

  /// When true, [readAll] throws.
  bool failReadAll = false;

  /// When true, [read] throws.
  bool failRead = false;

  /// When true, [delete] throws.
  bool failDelete = false;

  /// When true, [write] throws.
  bool failWrite = false;

  @override
  Future<StoredKey?> read(String instanceKey) async {
    if (failRead) throw StateError('keystore read failed');
    return _values[instanceKey];
  }

  @override
  Future<void> write(String instanceKey, StoredKey key) async {
    if (failWrite) throw StateError('keystore write failed');
    _values[instanceKey] = key;
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
}
