import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/app/app.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/app/router.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/stored_key.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/features/issues/issue_thread.dart';
import 'package:paperplane/ui/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/network_status.dart';

/// Time the issue tests run at.
final issueTestNow = DateTime.utc(2026, 1, 15, 12);

/// Fake [FakeIssueRepository] with a gate, so a test can hold the POST back
/// and look at the pending state.
class GatedIssueRepository extends FakeIssueRepository {
  /// Creates the repository at [issueTestNow].
  new() : super(now: () => issueTestNow);
}

/// What an issue test drives and inspects.
class IssueHarness {
  /// Creates the harness.
  new({
    required this.container,
    required this.issues,
    required this.opened,
    required this.agents,
  });

  /// The provider container of the running app.
  final ProviderContainer container;

  /// Issue fake.
  final FakeIssueRepository issues;

  /// Agent fake.
  final FakeAgentRepository agents;

  /// URLs handed to the browser.
  final List<Uri> opened;
}

/// Runs the whole app signed in on fakes and opens `/issues/[issueId]`.
Future<IssueHarness> pumpIssue(
  WidgetTester tester, {
  String issueId = 'ACM-12',
  FakeIssueRepository? issues,
  FakeAgentRepository? agents,
  Size size = const Size(390, 844),
  bool browserOpens = true,
  double textScale = 1,
  bool settle = true,
  Widget Function(Widget app)? wrapApp,
}) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  addTearDown(dismissAppToast);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final base = Uri.parse('https://x.example.test');
  SharedPreferences.setMockInitialValues({'last_base_url': base.toString()});
  final keys = InMemoryKeyStore();
  await keys.write(
    base.toString(),
    StoredKey(token: 'fake-key', createdAt: DateTime.now()),
  );

  final fakeIssues = issues ?? GatedIssueRepository();
  final fakeAgents = agents ?? FakeAgentRepository();
  final opened = <Uri>[];
  var counter = 0;

  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appPrefsProvider.overrideWithValue(
        AppPrefs(await SharedPreferences.getInstance()),
      ),
      keyStoreProvider.overrideWithValue(keys),
      appEnvProvider.overrideWith(() => AppEnvController(const AppEnv())),
      inboxRepositoryProvider.overrideWithValue(
        FakeInboxRepository(now: () => issueTestNow),
      ),
      companyRepositoryProvider.overrideWithValue(FakeCompanyRepository()),
      sessionRepositoryProvider.overrideWithValue(FakeSessionRepository()),
      issueRepositoryProvider.overrideWithValue(fakeIssues),
      agentRepositoryProvider.overrideWithValue(fakeAgents),
      networkStatusServiceProvider.overrideWithValue(FakeNetworkStatus()),
      clockProvider.overrideWithValue(() => issueTestNow),
      clientRequestIdProvider.overrideWithValue(() => 'req-${++counter}'),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return browserOpens;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: wrapApp == null
          ? const PaperplaneApp()
          : wrapApp(const PaperplaneApp()),
    ),
  );
  await tester.pumpAndSettle();
  // ignore: unawaited_futures, the push completes when the screen pops.
  container.read(routerProvider).push('/issues/$issueId');
  if (settle) await tester.pumpAndSettle();
  return IssueHarness(
    container: container,
    issues: fakeIssues,
    agents: fakeAgents,
    opened: opened,
  );
}
