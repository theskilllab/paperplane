import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/ui/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider overrides for tests that run the whole app on fake storage.
Future<List<Override>> appOverrides({
  bool demo = false,
  Map<String, Object> prefs = const {},
  Map<String, String> keys = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = InMemoryKeyStore();
  for (final entry in keys.entries) {
    await store.write(entry.key, entry.value);
  }
  return [
    appPrefsProvider.overrideWithValue(
      AppPrefs(await SharedPreferences.getInstance()),
    ),
    keyStoreProvider.overrideWithValue(store),
    appEnvProvider.overrideWith(() => AppEnvController(AppEnv(demo: demo))),
  ];
}

/// Wraps [child] in the Paperplane theme, for component tests.
Widget themed(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: buildPaperplaneTheme(),
  home: MediaQuery.fromView(
    view: WidgetsBinding.instance.platformDispatcher.views.first,
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: Scaffold(body: child),
      ),
    ),
  ),
);
