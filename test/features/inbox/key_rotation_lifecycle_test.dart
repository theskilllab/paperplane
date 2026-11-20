import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/auth/stored_key.dart';
import 'package:paperplane/data/auth_repository.dart';

import '../../support/fake_adapter.dart';
import 'inbox_harness.dart';

/// Pumps until [done] or a short time passes. The app's rotation runs behind
/// an `await`, so a widget test must give the fake clock a chance to advance.
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  testWidgets(
    'a key that ages while the app is open rotates on resume, even when the '
    'app is backgrounded mid-swap',
    (tester) async {
      final started = Completer<void>();
      final release = Completer<void>();
      var mints = 0;
      final adapter = FakeAdapter((o) async {
        switch ('${o.method} ${o.path}') {
          case 'POST /board-api-keys':
            mints++;
            started.complete();
            await release.future;
            return jsonBody({
              'id': 'key-new',
              'token': 'new-key',
              'expiresAt': testNow
                  .add(const Duration(days: 30))
                  .toIso8601String(),
            }, status: 201);
          case 'DELETE /board-api-keys/key-old':
            return jsonBody(<String, Object?>{});
          default:
            fail('unexpected ${o.method} ${o.path}');
        }
      });
      final keys = InMemoryKeyStore();
      final h = await pumpInbox(
        tester,
        keyStore: keys,
        rotationRepository: HttpAuthRepository(
          adapter: adapter,
          now: () => testNow,
        ),
      );

      // The stored key turns eight days old while the app is open.
      await keys.write(
        h.baseUrl.toString(),
        StoredKey(
          token: 'fake-key',
          keyId: 'key-old',
          createdAt: testNow.subtract(const Duration(days: 8)),
        ),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpUntil(tester, () => started.isCompleted);
      expect(started.isCompleted, isTrue, reason: 'rotation did not start');

      // The user backgrounds the app before the mint answers. The in-flight
      // rotation must still settle, and must store the new key.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      release.complete();
      await pumpUntil(
        tester,
        () =>
            h.container.read(sessionControllerProvider) is SignedIn &&
            (h.container.read(sessionControllerProvider) as SignedIn).token ==
                'new-key',
      );

      expect(mints, 1);
      expect((await keys.read(h.baseUrl.toString()))?.token, 'new-key');
      final state = h.container.read(sessionControllerProvider) as SignedIn;
      expect(state.token, 'new-key');
    },
  );
}
