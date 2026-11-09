import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/app/app.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      // The app never retries a failed provider on its own: the user taps
      // Retry, and writes must not repeat.
      retry: (_, _) => null,
      overrides: [appPrefsProvider.overrideWithValue(AppPrefs(prefs))],
      child: const PaperplaneApp(),
    ),
  );
}
