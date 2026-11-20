import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/app/app.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/app/router.dart';
import 'package:paperplane/app/routes.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/features/approvals/approval_screen.dart';
import 'package:paperplane/features/inbox/inbox_screen.dart';
import 'package:paperplane/features/issues/issue_screen.dart';
import 'package:paperplane/features/issues/new_issue_screen.dart';

import '../support/app_harness.dart';

Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  bool demo = true,
  Map<String, Object> prefs = const {},
  Map<String, String> keys = const {},
}) async {
  // Signed-in tests that are not in demo mode still must not reach a network:
  // answer from the fakes.
  final overrides = [
    ...await appOverrides(demo: demo, prefs: prefs, keys: keys),
    if (!demo) ...[
      companyRepositoryProvider.overrideWithValue(FakeCompanyRepository()),
      inboxRepositoryProvider.overrideWithValue(FakeInboxRepository()),
      approvalRepositoryProvider.overrideWithValue(FakeApprovalRepository()),
    ],
  ];
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: overrides,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PaperplaneApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('redirectFor', () {
    final signedIn = SignedIn(
      baseUrl: Uri.parse('https://x.example.test'),
      token: 't',
    );

    test('restoring waits on the splash', () {
      expect(redirectFor(const SessionRestoring(), '/'), AppRoutes.splash);
      expect(redirectFor(const SessionRestoring(), AppRoutes.splash), isNull);
    });

    test('signed out may only see S1', () {
      expect(redirectFor(const SignedOut(), '/'), AppRoutes.connect);
      expect(
        redirectFor(const SignedOut(), '/approvals/a1'),
        AppRoutes.connect,
      );
      expect(redirectFor(const SignedOut(), AppRoutes.connect), isNull);
    });

    test('signed in leaves S1 and the splash', () {
      expect(redirectFor(signedIn, AppRoutes.connect), AppRoutes.inbox);
      expect(redirectFor(signedIn, AppRoutes.splash), AppRoutes.inbox);
      expect(redirectFor(signedIn, '/issues/ABC-1'), isNull);
    });
  });

  group('routes', () {
    testWidgets('demo mode opens S2 Inbox', (tester) async {
      await pumpApp(tester);
      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('every S1–S7 route resolves to its own screen', (tester) async {
      final container = await pumpApp(tester);
      final router = container.read(routerProvider);
      Future<void> go(String location) async {
        router.go(location);
        await tester.pumpAndSettle();
      }

      await go(AppRoutes.interaction('ABC-1', 'int-1'));
      expect(find.text('S5 Question'), findsWidgets);

      await go(AppRoutes.newIssue);
      expect(find.byType(NewIssueScreen), findsOneWidget);

      await go(AppRoutes.issue('ACM-12'));
      expect(find.text('ACM-12'), findsWidgets);

      await go(AppRoutes.approval('appr-1'));
      expect(find.byType(ApprovalScreen), findsOneWidget);
      expect(find.text('Hire an agent'), findsNothing);
      await go(AppRoutes.inbox);
      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('"new" is S7, not an issue called "new"', (tester) async {
      final container = await pumpApp(tester);
      container.read(routerProvider).go('/issues/new');
      await tester.pumpAndSettle();
      expect(find.byType(NewIssueScreen), findsOneWidget);
      expect(find.byType(IssueScreen), findsNothing);
    });

    test('path helpers encode ids', () {
      expect(AppRoutes.approval('a/b'), '/approvals/a%2Fb');
      expect(AppRoutes.issue('A B'), '/issues/A%20B');
    });

    testWidgets('signed out lands on S1, then signs in to S2', (tester) async {
      final container = await pumpApp(tester, demo: false);
      expect(find.text('Connect to your Paperclip'), findsWidgets);

      await container
          .read(sessionControllerProvider.notifier)
          .signIn(baseUrl: Uri.parse('https://x.example.test'), token: 't');
      await tester.pumpAndSettle();
      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('"Explore the demo" on S1 opens the demo Inbox', (
      tester,
    ) async {
      await pumpApp(tester, demo: false);
      expect(find.text('Connect to your Paperclip'), findsWidgets);

      await tester.scrollUntilVisible(
        find.text('Explore the demo'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Explore the demo'));
      await tester.pumpAndSettle();

      expect(find.byType(InboxScreen), findsOneWidget);
      expect(find.text('Acme Demo'), findsOneWidget);
    });

    testWidgets('a 401 moves a signed-in user to S1', (tester) async {
      final container = await pumpApp(
        tester,
        demo: false,
        prefs: {'last_base_url': 'https://x.example.test'},
        keys: {'https://x.example.test': 'fake-key'},
      );
      expect(find.byType(InboxScreen), findsOneWidget);

      await container
          .read(sessionControllerProvider.notifier)
          .handleUnauthorized();
      await tester.pumpAndSettle();
      expect(find.text('Connect to your Paperclip'), findsWidgets);
    });
  });
}
