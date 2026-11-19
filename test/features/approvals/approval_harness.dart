import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/features/approvals/approval_screen.dart';
import 'package:paperplane/features/inbox/company_providers.dart';
import 'package:paperplane/ui/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../inbox/inbox_harness.dart' show testNow;

/// The demo approval row, as the Inbox would pass it to S4.
AttentionItem demoApprovalItem({bool inlineResolvable = true}) {
  final feed = AttentionFeed.fromJson(demoAttentionJson(testNow));
  final item = feed.items.firstWhere((item) => item.id == 'att-01');
  return inlineResolvable
      ? item
      : AttentionItem(
          id: item.id,
          sourceKind: item.sourceKind,
          title: item.title,
          summary: item.summary,
          subject: item.subject,
          createdAt: item.createdAt,
          activityAt: item.activityAt,
        );
}

/// Everything a test needs to drive and inspect S4.
class ApprovalHarness {
  /// Creates the harness.
  const new({
    required this.container,
    required this.approvals,
    required this.inbox,
    required this.opened,
  });

  /// The app's provider container.
  final ProviderContainer container;

  /// Approval fake.
  final FakeApprovalRepository approvals;

  /// Inbox fake, for row removal.
  final FakeInboxRepository inbox;

  /// URLs handed to the browser.
  final List<Uri> opened;
}

/// Opens S4 on top of a plain route, so a successful decision can pop back.
Future<ApprovalHarness> pumpApproval(
  WidgetTester tester, {
  String approvalId = 'appr-01',
  AttentionItem? attention,
  FakeApprovalRepository? approvals,
  FakeInboxRepository? inbox,
  bool demo = true,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final base = Uri.parse('https://x.example.test');
  SharedPreferences.setMockInitialValues({
    if (!demo) 'last_base_url': base.toString(),
  });
  final prefs = AppPrefs(await SharedPreferences.getInstance());
  final keys = InMemoryKeyStore();
  if (!demo) await keys.write(base.toString(), 'fake-key');
  final fakeApprovals = approvals ?? FakeApprovalRepository(now: () => testNow);
  final fakeInbox = inbox ?? FakeInboxRepository(now: () => testNow);
  final opened = <Uri>[];
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appPrefsProvider.overrideWithValue(prefs),
      keyStoreProvider.overrideWithValue(keys),
      appEnvProvider.overrideWith(() => AppEnvController(AppEnv(demo: demo))),
      companyRepositoryProvider.overrideWithValue(FakeCompanyRepository()),
      sessionRepositoryProvider.overrideWithValue(FakeSessionRepository()),
      approvalRepositoryProvider.overrideWithValue(fakeApprovals),
      inboxRepositoryProvider.overrideWithValue(fakeInbox),
      clockProvider.overrideWithValue(() => testNow),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
      }),
    ],
  );
  addTearDown(container.dispose);

  await container.read(companiesProvider.future);
  final row = attention ?? demoApprovalItem();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildPaperplaneTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ApprovalScreen(
                        approvalId: approvalId,
                        attention: row,
                      ),
                    ),
                  ),
                  child: const Text('open approval'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open approval'));
  await tester.pumpAndSettle();

  return ApprovalHarness(
    container: container,
    approvals: fakeApprovals,
    inbox: fakeInbox,
    opened: opened,
  );
}
