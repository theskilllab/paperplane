import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/features/inbox/inbox_screen.dart';
import 'package:paperplane/ui/ui.dart';

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
      expect(await h.keys.read(h.baseUrl.toString()), 'fake-key');
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
      expect(find.text('S1 Connect'), findsWidgets);
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
      expect(find.text('S1 Connect'), findsWidgets);
      expect(find.textContaining('may stay active'), findsOneWidget);
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
      expect(find.text('S1 Connect'), findsWidgets);
    });
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
  });
}
