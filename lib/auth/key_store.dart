import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:paperplane/auth/stored_key.dart';

/// Where board keys live. One key per server address.
///
/// Keys are credentials. They are written only here, read only by the session
/// controller, and never logged, printed or put in preferences.
abstract interface class KeyStore {
  /// Returns the key stored for [instanceKey], or null.
  Future<StoredKey?> read(String instanceKey);

  /// Stores [key] for [instanceKey], replacing any earlier key in one write.
  Future<void> write(String instanceKey, StoredKey key);

  /// Removes the key stored for [instanceKey].
  Future<void> delete(String instanceKey);

  /// Every stored key, by instance address.
  ///
  /// Used once at first start to remove a key that an earlier install left in
  /// the iOS Keychain. Keychain items survive an app reinstall while the
  /// preferences that name their server do not, so without this the key would
  /// be orphaned forever.
  ///
  /// Returns an empty map on macOS, where the legacy login keychain cannot run
  /// that query.
  Future<Map<String, StoredKey>> readAll();
}

/// [KeyStore] on the platform keystore: Keychain on iOS and macOS,
/// Keystore-backed encryption on Android.
///
/// iOS uses `first_unlock_this_device`, so keys are not synced to iCloud and
/// do not move to a new device. Android sets `allowBackup="false"` in the
/// manifest for the same reason.
///
/// macOS test builds are ad-hoc signed, with no team or keychain access
/// group. The data-protection keychain needs both, so macOS uses the legacy
/// file-based login keychain instead (`usesDataProtectionKeychain: false`).
/// It also does not sync, so the "never synced" rule still holds.
class SecureKeyStore implements KeyStore {
  /// Creates the store. Pass [storage] only in tests.
  new({FlutterSecureStorage? storage, DateTime Function()? now})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          ),
      _now = now ?? DateTime.now;

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;

  static const _prefix = 'board_key:';

  static String _name(String instanceKey) => '$_prefix$instanceKey';

  @override
  Future<StoredKey?> read(String instanceKey) async {
    final raw = await _storage.read(key: _name(instanceKey));
    if (raw == null) return null;
    final key = StoredKey.decode(raw, now: _now());
    return key.isUsable ? key : null;
  }

  @override
  Future<void> write(String instanceKey, StoredKey key) =>
      _storage.write(key: _name(instanceKey), value: key.encode());

  @override
  Future<void> delete(String instanceKey) =>
      _storage.delete(key: _name(instanceKey));

  @override
  Future<Map<String, StoredKey>> readAll() async {
    // The macOS login keychain is file-based and rejects the plugin's
    // all-items query (`kSecMatchLimitAll` with `kSecReturnData`) with
    // `errSecParam`. Orphan cleanup only matters on iOS after a reinstall, so
    // the macOS test build skips it.
    if (defaultTargetPlatform == TargetPlatform.macOS) return {};
    final all = await _storage.readAll();
    return {
      for (final entry in all.entries)
        if (entry.key.startsWith(_prefix))
          entry.key.substring(_prefix.length): StoredKey.decode(
            entry.value,
            now: _now(),
          ),
    };
  }
}

/// [KeyStore] in memory. For tests and demo mode; nothing is persisted.
class InMemoryKeyStore implements KeyStore {
  final Map<String, StoredKey> _values = {};

  @override
  Future<StoredKey?> read(String instanceKey) async => _values[instanceKey];

  @override
  Future<void> write(String instanceKey, StoredKey key) async {
    _values[instanceKey] = key;
  }

  @override
  Future<void> delete(String instanceKey) async {
    _values.remove(instanceKey);
  }

  @override
  Future<Map<String, StoredKey>> readAll() async => Map.of(_values);
}
