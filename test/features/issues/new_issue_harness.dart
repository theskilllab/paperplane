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
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/ui/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/network_status.dart';
import '../inbox/inbox_harness.dart' show TrackingInbox, testNow;

/// What an S7 test drives and inspects.
class NewIssueHarness {
  /// Creates the harness.
  new({
    required this.container,
    required this.issues,
    required this.agents,
    required this.projects,
    required this.inbox,
    required this.opened,
  });

  /// The provider container of the running app.
  final ProviderContainer container;

  /// Issue fake.
  final FakeIssueRepository issues;

  /// Agent fake.
  final FakeAgentRepository agents;

  /// Project fake.
  final FakeProjectRepository projects;

  /// Inbox fake, for the AC4 refresh count.
  final TrackingInbox inbox;

  /// URLs handed to the browser.
  final List<Uri> opened;
}

/// Runs the whole app signed in on fakes and opens `/issues/new`.
Future<NewIssueHarness> pumpNewIssue(
  WidgetTester tester, {
  FakeIssueRepository? issues,
  FakeAgentRepository? agents,
  FakeProjectRepository? projects,
  TrackingInbox? inbox,
  Size size = const Size(390, 844),
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
  await keys.write(base.toString(), 'fake-key');

  final fakeIssues = issues ?? FakeIssueRepository(now: () => testNow);
  final fakeAgents = agents ?? FakeAgentRepository();
  final fakeProjects = projects ?? FakeProjectRepository();
  final fakeInbox = inbox ?? TrackingInbox();
  final opened = <Uri>[];

  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appPrefsProvider.overrideWithValue(
        AppPrefs(await SharedPreferences.getInstance()),
      ),
      keyStoreProvider.overrideWithValue(keys),
      appEnvProvider.overrideWith(() => AppEnvController(const AppEnv())),
      inboxRepositoryProvider.overrideWithValue(fakeInbox),
      companyRepositoryProvider.overrideWithValue(FakeCompanyRepository()),
      sessionRepositoryProvider.overrideWithValue(FakeSessionRepository()),
      issueRepositoryProvider.overrideWithValue(fakeIssues),
      agentRepositoryProvider.overrideWithValue(fakeAgents),
      projectRepositoryProvider.overrideWithValue(fakeProjects),
      networkStatusServiceProvider.overrideWithValue(FakeNetworkStatus()),
      clockProvider.overrideWithValue(() => testNow),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
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
  container.read(routerProvider).push('/issues/new');
  if (settle) await tester.pumpAndSettle();
  return NewIssueHarness(
    container: container,
    issues: fakeIssues,
    agents: fakeAgents,
    projects: fakeProjects,
    inbox: fakeInbox,
    opened: opened,
  );
}
