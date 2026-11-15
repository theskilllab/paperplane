import 'dart:async';

import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/auth/device_name.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/data/auth_repository.dart';
import 'package:paperplane/data/company_repository.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/data/inbox_repository.dart';
import 'package:paperplane/data/session_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// Replaces Dio's network adapter. Null in the app; tests override it to answer
/// requests without a network.
final httpAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

/// HTTP client for the signed-in instance.
///
/// Rebuilt when the session changes. A 401 makes it call
/// `SessionController.handleUnauthorized` (PRD G3). While signed out, or in
/// demo mode, it is a client whose calls fail with `Unauthorized` and never
/// touch the network.
final apiClientProvider = Provider<ApiClient>((ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session is! SignedIn || session.isDemo) return ApiClient.signedOut();

  final client = ApiClient(
    baseUrl: session.baseUrl,
    tokenProvider: () => session.token,
    onUnauthorized: (usedToken) => unawaited(
      ref
          .read(sessionControllerProvider.notifier)
          .handleUnauthorized(usedToken),
    ),
    // Redacted, path-only lines. Off in release builds.
    log: kDebugMode ? debugPrint : null,
    adapter: ref.watch(httpAdapterProvider),
  );
  ref.onDispose(client.close);
  return client;
});

/// Sign-in and device-login calls, before a session exists. Uses the same
/// HTTP adapter override as the signed-in client, so tests need no network.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => HttpAuthRepository(adapter: ref.watch(httpAdapterProvider)),
);

/// Device label for the board-key name, for example `iPhone`.
final deviceNameProvider = Provider<String>((ref) => platformDeviceName());

/// Session facts. Fake in demo mode.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  if (ref.watch(appEnvProvider).demo) return FakeSessionRepository();
  return HttpSessionRepository(ref.watch(apiClientProvider));
});

/// Companies. Fake in demo mode.
final companyRepositoryProvider = Provider<CompanyRepository>((ref) {
  if (ref.watch(appEnvProvider).demo) return FakeCompanyRepository();
  return HttpCompanyRepository(
    ref.watch(apiClientProvider),
    prefs: ref.watch(appPrefsProvider),
  );
});

/// Inbox feed. Fake in demo mode.
final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  if (ref.watch(appEnvProvider).demo) return FakeInboxRepository();
  return HttpInboxRepository(
    ref.watch(apiClientProvider),
    prefs: ref.watch(appPrefsProvider),
    now: ref.watch(clockProvider),
  );
});

/// The current time. Tests override it so ages and "Last updated" are fixed.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Opens a web page in the system browser and says whether it worked.
///
/// The PR 1 stopgap for rows whose detail screen does not exist yet. Tests
/// override it; nothing else opens URLs.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
