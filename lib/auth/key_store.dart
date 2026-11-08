import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where board keys live. One key per server address.
///
/// Keys are credentials. They are written only here, read only by the session
/// controller, and never logged, printed or put in preferences.
abstract interface class KeyStore {
  /// Returns the key stored for [instanceKey], or null.
  Future<String?> read(String instanceKey);

  /// Stores [token] for [instanceKey], replacing any earlier key.
  Future<void> write(String instanceKey, String token);

  /// Removes the key stored for [instanceKey].
  Future<void> delete(String instanceKey);
}

/// [KeyStore] on the platform keystore: Keychain on iOS, Keystore-backed
/// encryption on Android.
///
/// iOS uses `first_unlock_this_device`, so keys are not synced to iCloud and
/// do not move to a new device. Android sets `allowBackup="false"` in the
/// manifest for the same reason.
class SecureKeyStore implements KeyStore {
  /// Creates the store. Pass [storage] only in tests.
  new({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static String _name(String instanceKey) => 'board_key:$instanceKey';

  @override
  Future<String?> read(String instanceKey) =>
      _storage.read(key: _name(instanceKey));

  @override
  Future<void> write(String instanceKey, String token) =>
      _storage.write(key: _name(instanceKey), value: token);

  @override
  Future<void> delete(String instanceKey) =>
      _storage.delete(key: _name(instanceKey));
}

/// [KeyStore] in memory. For tests and demo mode; nothing is persisted.
class InMemoryKeyStore implements KeyStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String instanceKey) async => _values[instanceKey];

  @override
  Future<void> write(String instanceKey, String token) async {
    _values[instanceKey] = token;
  }

  @override
  Future<void> delete(String instanceKey) async {
    _values.remove(instanceKey);
  }
}
