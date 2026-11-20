import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paperplane/app/app.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/stored_key.dart';
import 'package:paperplane/features/connect/connect_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs on the macOS CI runner only (`flutter test integration_test -d macos`).
///
/// It proves that the ad-hoc signed, sandboxed app can use the login keychain
/// and that a real start reaches the sign-in screen even when the keychain is
/// empty. The values here are fake; nothing touches the network.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the macOS keystore round trips', (tester) async {
    final store = SecureKeyStore();
    final instance =
        'https://paperplane-smoke-'
        '${DateTime.now().microsecondsSinceEpoch}.invalid';
    const token = 'pcp_board_fake_smoke_key';

    await store.write(
      instance,
      StoredKey(token: token, createdAt: DateTime.now()),
    );
    expect((await store.read(instance))?.token, token);
    expect(await store.readAll(), isA<Map<String, StoredKey>>());
    await store.delete(instance);
    expect(await store.read(instance), isNull);
  });

  testWidgets('a real start leaves the splash for sign-in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appPrefsProvider.overrideWithValue(
          AppPrefs(await SharedPreferences.getInstance()),
        ),
        appEnvProvider.overrideWith(() => AppEnvController(const AppEnv())),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PaperplaneApp(),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ConnectScreen).evaluate().isNotEmpty) break;
    }

    expect(
      find.byType(ConnectScreen),
      findsOneWidget,
      reason: 'The session restore did not leave the splash screen.',
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
