import 'package:paperplane/auth/key_store.dart';

/// [KeyStore] that can fail any operation, for start-up and sign-out tests.
class ThrowingKeyStore implements KeyStore {
  /// Creates a store holding [values]. Failures are off until a flag is set.
  new({Map<String, String> values = const {}}) : _values = Map.of(values);

  final Map<String, String> _values;

  /// When true, [readAll] throws.
  bool failReadAll = false;

  /// When true, [read] throws.
  bool failRead = false;

  /// When true, [delete] throws.
  bool failDelete = false;

  /// When true, [write] throws.
  bool failWrite = false;

  @override
  Future<String?> read(String instanceKey) async {
    if (failRead) throw StateError('keystore read failed');
    return _values[instanceKey];
  }

  @override
  Future<void> write(String instanceKey, String token) async {
    if (failWrite) throw StateError('keystore write failed');
    _values[instanceKey] = token;
  }

  @override
  Future<void> delete(String instanceKey) async {
    if (failDelete) throw StateError('keystore delete failed');
    _values.remove(instanceKey);
  }

  @override
  Future<Map<String, String>> readAll() async {
    if (failReadAll) throw StateError('keystore readAll failed');
    return Map.of(_values);
  }
}
