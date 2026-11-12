import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/app/app.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/ui/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Time every test in this folder runs at. Demo ages are relative to it.
final testNow = DateTime.utc(2026, 11, 9, 12);

/// [FakeInboxRepository] that counts feed calls and can be gated by a test.
class TrackingInbox extends FakeInboxRepository {
  /// Creates the repository at [testNow].
  new() : super(now: () => testNow);

  /// Number of `fetchAttention` calls.
  int feedCalls = 0;

  /// When set, answers `fetchAttention` instead of the canned feed. Lets a
  /// test hold an answer back and release it later.
  Future<AttentionFeed> Function(String companyId)? onFetch;

  @override
  Future<AttentionFeed> fetchAttention(
    String companyId, {
    int limit = 100,
  }) async {
    feedCalls++;
    final handler = onFetch;
    if (handler != null) {
      await simulate();
      return await handler(companyId);
    }
    return await super.fetchAttention(companyId, limit: limit);
  }
}

/// Everything a test needs to drive and inspect the running app.
class InboxHarness {
  /// Creates the harness.
  new({
    required this.container,
    required this.inbox,
    required this.companies,
    required this.session,
    required this.keys,
    required this.opened,
    required this.baseUrl,
  });

  /// The app's provider container.
  final ProviderContainer container;

  /// Inbox fake.
  final TrackingInbox inbox;

  /// Company fake.
  final FakeCompanyRepository companies;

  /// Session fake (revoke).
  final FakeSessionRepository session;

  /// Key store.
  final InMemoryKeyStore keys;

  /// URLs handed to the browser.
  final List<Uri> opened;

  /// Server address of a signed-in (non-demo) session.
  final Uri baseUrl;
}

/// Runs the whole app on fakes and waits for the first load.
///
/// [demo] = true uses the built-in demo session; otherwise it is a signed-in
/// session on [baseUrl] with a fake key. The window is a 390×844 phone unless
/// [size] says otherwise. [settle] = false returns right after the first
/// frame, for tests of the loading state.
Future<InboxHarness> pumpInbox(
  WidgetTester tester, {
  bool demo = false,
  Uri? baseUrl,
  Map<String, Object> prefs = const {},
  TrackingInbox? inbox,
  FakeCompanyRepository? companies,
  FakeSessionRepository? session,
  Size size = const Size(390, 844),
  bool settle = true,
  bool browserOpens = true,
  Widget Function(Widget app)? wrapApp,
}) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  addTearDown(dismissAppToast);

  final base = baseUrl ?? Uri.parse('https://x.example.test');
  SharedPreferences.setMockInitialValues({
    if (!demo) 'last_base_url': base.toString(),
    ...prefs,
  });
  final keys = InMemoryKeyStore();
  if (!demo) await keys.write(base.toString(), 'fake-key');

  final fakeInbox = inbox ?? TrackingInbox();
  final fakeCompanies = companies ?? FakeCompanyRepository();
  final fakeSession = session ?? FakeSessionRepository();
  final opened = <Uri>[];

  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appPrefsProvider.overrideWithValue(
        AppPrefs(await SharedPreferences.getInstance()),
      ),
      keyStoreProvider.overrideWithValue(keys),
      appEnvProvider.overrideWith(() => AppEnvController(AppEnv(demo: demo))),
      inboxRepositoryProvider.overrideWithValue(fakeInbox),
      companyRepositoryProvider.overrideWithValue(fakeCompanies),
      sessionRepositoryProvider.overrideWithValue(fakeSession),
      clockProvider.overrideWithValue(() => testNow),
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
  if (settle) await tester.pumpAndSettle();
  return InboxHarness(
    container: container,
    inbox: fakeInbox,
    companies: fakeCompanies,
    session: fakeSession,
    keys: keys,
    opened: opened,
    baseUrl: base,
  );
}
