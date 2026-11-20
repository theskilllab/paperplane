import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/auth/stored_key.dart';
import 'package:paperplane/data/auth_repository.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/features/inbox/inbox_screen.dart';
import 'package:paperplane/ui/ui.dart';

import '../../support/fake_adapter.dart';
import '../../support/throwing_key_store.dart';
import 'inbox_harness.dart';

Future<void> scrollToAccountRow(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Sign out'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  group('Sign out from the account row (S1 AC10, design spec D4)', () {
    testWidgets('shows the server and a Sign out button at the bottom', (
      tester,
    ) async {
      await pumpInbox(tester);

      await scrollToAccountRow(tester);

      expect(find.text('x.example.test'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('asks first; Cancel changes nothing', (tester) async {
      final h = await pumpInbox(tester);
      await scrollToAccountRow(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Disconnect this server?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect this server?'), findsNothing);
      expect(find.byType(InboxScreen), findsOneWidget);
      expect(h.session.revokeCount, 0);
      expect((await h.keys.read(h.baseUrl.toString()))?.token, 'fake-key');
    });

    testWidgets('Disconnect revokes the key, deletes it and shows S1', (
      tester,
    ) async {
      final h = await pumpInbox(tester);
      await scrollToAccountRow(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(h.session.revokeCount, 1);
      expect(await h.keys.read(h.baseUrl.toString()), isNull);
      expect(find.text('Connect to your Paperclip'), findsWidgets);
      expect(find.byType(InboxScreen), findsNothing);
      expect(find.text('Disconnect this server?'), findsNothing);
    });

    testWidgets('offline: still signs out here and says the key may live on', (
      tester,
    ) async {
      final session = FakeSessionRepository()..failWith = const Offline();
      final h = await pumpInbox(tester, session: session);
      await scrollToAccountRow(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(await h.keys.read(h.baseUrl.toString()), isNull);
      expect(find.text('Connect to your Paperclip'), findsWidgets);
      expect(find.textContaining('may stay active'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a local delete failure does not report success', (
      tester,
    ) async {
      final store = ThrowingKeyStore();
      final h = await pumpInbox(tester, keyStore: store);
      store.failDelete = true;
      await scrollToAccountRow(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(h.session.revokeCount, 1);
      expect(await h.keys.read(h.baseUrl.toString()), isNotNull);
      expect(find.text('Connect to your Paperclip'), findsWidgets);
      expect(find.text('Sign-out incomplete'), findsOneWidget);
      expect(
        find.textContaining('Signed out here, but this device'),
        findsOneWidget,
      );
      final state = h.container.read(sessionControllerProvider) as SignedOut;
      expect(state.cleanupPending, isTrue);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('an already-invalid key is not reported as a failure', (
      tester,
    ) async {
      final session = FakeSessionRepository()..failWith = const Unauthorized();
      final h = await pumpInbox(tester, session: session);
      await scrollToAccountRow(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(await h.keys.read(h.baseUrl.toString()), isNull);
      expect(find.textContaining('may stay active'), findsNothing);
    });

    testWidgets('the button shows progress and cannot be tapped twice', (
      tester,
    ) async {
      final session = FakeSessionRepository()
        ..latency = const Duration(seconds: 2);
      final h = await pumpInbox(tester, session: session);
      await scrollToAccountRow(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pump(const Duration(milliseconds: 100));
      final sheet = find.byType(AppSheet);
      expect(
        find.descendant(
          of: sheet,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: sheet, matching: find.byType(AppButton)).first,
        warnIfMissed: false,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(h.session.revokeCount, 1);
    });

    testWidgets('from the switcher footer too', (tester) async {
      final h = await pumpInbox(tester);

      await tester.tap(find.text('Acme Demo'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppSheet),
          matching: find.text('Sign out'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Disconnect this server?'), findsOneWidget);
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(h.session.revokeCount, 1);
      expect(find.text('Connect to your Paperclip'), findsWidgets);
    });
    testWidgets(
      'sign-out marks the session before the revoke request returns',
      (tester) async {
        final adapter = FakeAdapter((o) async {
          fail(
            'no rotation request during sign-out, got ${o.method} ${o.path}',
          );
        });
        final session = FakeSessionRepository()
          ..latency = const Duration(seconds: 2);
        final h = await pumpInbox(
          tester,
          session: session,
          rotationRepository: HttpAuthRepository(adapter: adapter),
        );
        await h.keys.write(
          h.baseUrl.toString(),
          StoredKey(
            token: 'fake-key',
            keyId: 'key-old',
            createdAt: testNow.subtract(const Duration(days: 8)),
          ),
        );

        await scrollToAccountRow(tester);
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Disconnect'));
        await tester.pump();

        // The server revoke is still in flight. A rotation must not start: if
        // it settled now, the sign-out would delete its key without revoking
        // it, leaving a live key on the server (S1 AC10).
        unawaited(
          h.container.read(sessionControllerProvider.notifier).rotateIfNeeded(),
        );
        // Let the rotation's read and mint run while the 2 s revoke is still
        // on the wire.
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(
          adapter.requests,
          isEmpty,
          reason: 'the rotation must stop once sign-out has started',
        );

        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(h.session.revokeCount, 1);
        expect(await h.keys.read(h.baseUrl.toString()), isNull);
      },
    );
  });

  group('Demo mode', () {
    testWidgets('labels the server as demo and leaves without a server', (
      tester,
    ) async {
      final h = await pumpInbox(tester, demo: true);
      await scrollToAccountRow(tester);
      expect(find.text('Demo'), findsOneWidget);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Leave the demo?'), findsOneWidget);
      await tester.tap(find.text('Leave demo'));
      await tester.pumpAndSettle();

      expect(h.session.revokeCount, 0);
      expect(h.container.read(appEnvProvider).demo, isFalse);
      expect(find.text('Explore the demo'), findsOneWidget);
    });

    testWidgets('account row does not overflow at 360 pt with XXL text', (
      tester,
    ) async {
      // XXL text on a 360 pt phone: the footer shows while the feed loads
      // (outside the list) and again at the end of the list.
      final h = await pumpInbox(
        tester,
        demo: true,
        size: const Size(360, 780),
        settle: false,
        wrapApp: (app) => MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(2),
          ),
          child: app,
        ),
      );
      expect(find.text('Demo'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      await scrollToAccountRow(tester);
      expect(find.text('Demo'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(h.session.revokeCount, 0);
    });
  });
}
