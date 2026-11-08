import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build- and run-time switches of the app.
@immutable
class AppEnv {
  /// Creates the environment. [demo] runs on fake data with no server.
  const new({this.demo = false});

  /// Reads `--dart-define=PAPERPLANE_DEMO=true`.
  const new fromEnvironment()
    : demo = const bool.fromEnvironment('PAPERPLANE_DEMO');

  /// True when every repository is a fake and no network is used.
  final bool demo;
}

/// Holds the [AppEnv]. S1 flips it to enter demo mode.
class AppEnvController extends Notifier<AppEnv> {
  /// Creates the controller. Tests pass [initial].
  new([this.initial]);

  /// Starting value. Null reads the build environment.
  final AppEnv? initial;

  @override
  AppEnv build() => initial ?? const AppEnv.fromEnvironment();

  /// Switches to fake data.
  void enterDemo() => state = const AppEnv(demo: true);

  /// Leaves demo mode.
  void exitDemo() => state = const AppEnv();
}

/// The current [AppEnv].
final appEnvProvider = NotifierProvider<AppEnvController, AppEnv>(
  AppEnvController.new,
);
