import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// The device's own view of whether it has a network path.
///
/// This is a hint, not a request result. `false` lets the UI show the offline
/// banner at once instead of waiting for a request to time out; `true` only
/// means the OS has a path, so requests still decide whether the server is
/// reachable.
abstract interface class NetworkStatus {
  /// The current state. True when the OS reports any network path.
  Future<bool> isOnline();

  /// Each change of the state. True when a path exists.
  Stream<bool> get changes;
}

/// [NetworkStatus] from `connectivity_plus`.
class PlatformNetworkStatus implements NetworkStatus {
  /// Creates the reader.
  const new();

  static Connectivity get _plugin => Connectivity();

  static bool _online(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async {
    try {
      return _online(await _plugin.checkConnectivity());
    } on Object {
      // The OS signal is optional. If the plugin cannot answer, let a real
      // request decide instead of hiding the Inbox.
      return true;
    }
  }

  @override
  Stream<bool> get changes async* {
    try {
      yield* _plugin.onConnectivityChanged.map(_online).distinct();
    } on Object {
      // Same fallback as [isOnline]: without change events the normal request
      // timeout and poll still apply.
    }
  }
}
