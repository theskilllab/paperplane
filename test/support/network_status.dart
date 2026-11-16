import 'dart:async';

import 'package:paperplane/core/network_status.dart';

/// [NetworkStatus] a test can change at will.
class FakeNetworkStatus implements NetworkStatus {
  /// Creates the fake, online by default.
  new({this.online = true});

  /// Current state.
  bool online;

  final _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get changes => _changes.stream;

  /// Changes the state and tells listeners, like the OS would.
  void setOnline({required bool online}) {
    if (online == this.online) return;
    this.online = online;
    _changes.add(online);
  }
}
