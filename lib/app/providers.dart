import 'dart:async';

import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/data/company_repository.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/data/inbox_repository.dart';
import 'package:paperplane/data/session_repository.dart';

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
    onUnauthorized: () => unawaited(
      ref.read(sessionControllerProvider.notifier).handleUnauthorized(),
    ),
    // Redacted, path-only lines. Off in release builds.
    log: kDebugMode ? debugPrint : null,
    adapter: ref.watch(httpAdapterProvider),
  );
  ref.onDispose(client.close);
  return client;
});

/// Session facts. Fake in demo mode.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  if (ref.watch(appEnvProvider).demo) return FakeSessionRepository();
  return HttpSessionRepository(ref.watch(apiClientProvider));
});

/// Companies. Fake in demo mode.
final companyRepositoryProvider = Provider<CompanyRepository>((ref) {
  if (ref.watch(appEnvProvider).demo) return FakeCompanyRepository();
  return HttpCompanyRepository(ref.watch(apiClientProvider));
});

/// Inbox feed. Fake in demo mode.
final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  if (ref.watch(appEnvProvider).demo) return FakeInboxRepository();
  return HttpInboxRepository(ref.watch(apiClientProvider));
});
