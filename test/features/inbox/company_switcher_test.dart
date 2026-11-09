import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/features/inbox/company_providers.dart';
import 'package:paperplane/features/inbox/inbox_controller.dart';
import 'package:paperplane/ui/ui.dart';

import 'inbox_harness.dart';

Future<void> openSwitcher(WidgetTester tester) async {
  await tester.tap(find.text('Acme Demo'));
  await tester.pumpAndSettle();
}

void main() {
  group('S3 AC1, AC2: the sheet', () {
    testWidgets('lists the companies and offers Sign out', (tester) async {
      await pumpInbox(tester);

      await openSwitcher(tester);

      expect(find.text('Switch company'), findsOneWidget);
      expect(find.text('Globex Demo'), findsOneWidget);
      expect(find.text('ACM'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppSheet),
          matching: find.text('Sign out'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('marks the active company for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpInbox(tester);

      await openSwitcher(tester);

      expect(
        find.bySemanticsLabel('Acme Demo, current company'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Switch to Globex Demo'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the header button is a 44 pt target', (tester) async {
      await pumpInbox(tester);

      final box = tester.getRect(
        find.ancestor(
          of: find.text('Acme Demo'),
          matching: find.byType(InkWell),
        ),
      );
      expect(box.height, greaterThanOrEqualTo(44));
    });

    testWidgets('with one company there is no switcher, only the name', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final companies = FakeCompanyRepository()
        ..companies = const [Company(id: 'only', name: 'Solo Demo')];
      await pumpInbox(tester, companies: companies);

      expect(find.text('Solo Demo'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('switch company')), findsNothing);
      await tester.tap(find.text('Solo Demo'));
      await tester.pumpAndSettle();
      expect(find.text('Switch company'), findsNothing);
      handle.dispose();
    });

    testWidgets('on a tablet the sheet is a centered form sheet', (
      tester,
    ) async {
      await pumpInbox(tester, size: const Size(820, 1180));

      await openSwitcher(tester);

      final sheet = tester.getRect(find.byType(AppSheet));
      expect(sheet.width, lessThanOrEqualTo(540));
      expect(sheet.center.dx, closeTo(410, 1));
    });
  });

  group('S3 AC3: switching', () {
    testWidgets('closes the sheet, reloads the Inbox, remembers the pick', (
      tester,
    ) async {
      final h = await pumpInbox(tester);
      expect(find.text('Hire a support agent'), findsOneWidget);

      await openSwitcher(tester);
      await tester.tap(find.text('Globex Demo'));
      await tester.pumpAndSettle();

      expect(find.text('Switch company'), findsNothing);
      expect(find.text('Approve the Q4 hiring plan'), findsOneWidget);
      expect(find.text('Hire a support agent'), findsNothing);
      expect(h.inbox.feedCalls, 2);
      expect(h.container.read(activeCompanyIdProvider), demoCompanyId2);
      // The header shows the new company's own total.
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('the last-used company is restored at the next start', (
      tester,
    ) async {
      await pumpInbox(tester, prefs: {'last_company_id': demoCompanyId2});

      expect(find.text('Globex Demo'), findsOneWidget);
      expect(find.text('Approve the Q4 hiring plan'), findsOneWidget);
    });

    testWidgets('a company that is no longer accessible falls back quietly', (
      tester,
    ) async {
      await pumpInbox(tester, prefs: {'last_company_id': 'company-gone'});

      expect(find.text('Acme Demo'), findsOneWidget);
      expect(find.text('Hire a support agent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the pick is written to preferences', (tester) async {
      final h = await pumpInbox(tester);

      await openSwitcher(tester);
      await tester.tap(find.text('Globex Demo'));
      await tester.pumpAndSettle();

      expect(h.container.read(appPrefsProvider).lastCompanyId, demoCompanyId2);
    });
  });

  group('S3 AC4: the list cannot be fetched', () {
    testWidgets('the cached list shows with a banner; the active one works', (
      tester,
    ) async {
      final h = await pumpInbox(tester);

      h.companies.failWith = const Offline();
      await openSwitcher(tester);

      expect(find.text("Can't refresh the list"), findsOneWidget);
      expect(find.text('Globex Demo'), findsOneWidget);
      // The Inbox behind the sheet still has its rows.
      expect(find.text('Hire a support agent'), findsOneWidget);
    });
  });

  group('S3 AC6: switching during a refresh', () {
    testWidgets('a late answer for the old company is dropped', (tester) async {
      final h = await pumpInbox(tester);
      final late = Completer<AttentionFeed>();
      h.inbox.onFetch = (companyId) => companyId == demoCompanyId
          ? late.future
          : Future.value(
              AttentionFeed.fromJson(demoSecondCompanyAttentionJson(testNow)),
            );

      // A refresh of Acme starts and its answer is held back...
      unawaited(
        h.container.read(inboxProvider(demoCompanyId).notifier).refresh(),
      );
      await tester.pump();
      // ...and the user switches to Globex.
      await openSwitcher(tester);
      await tester.tap(find.text('Globex Demo'));
      await tester.pumpAndSettle();
      expect(find.text('Approve the Q4 hiring plan'), findsOneWidget);

      // Acme's answer arrives now. It must not show up or throw.
      late.complete(AttentionFeed.fromJson(demoAttentionJson(testNow)));
      await tester.pumpAndSettle();

      expect(find.text('Approve the Q4 hiring plan'), findsOneWidget);
      expect(find.text('Hire a support agent'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
