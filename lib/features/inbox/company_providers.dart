import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/data/company_repository.dart';

/// The companies the signed-in user can read.
///
/// Cold start with a list kept from an earlier run: that list is the first
/// state, at once, and a fresh `GET /companies` replaces it behind the screen.
/// Without this the Inbox waited for the network (up to the 15 s timeout)
/// before it could even look for its cached feed (PRD S1 AC11).
///
/// Reloaded on pull-to-refresh and when the switcher opens. While a reload
/// runs, or after it failed, the previous list stays available (S3 AC4).
class Companies extends AsyncNotifier<List<Company>> {
  bool _started = false;
  int _builds = 0;

  @override
  Future<List<Company>> build() {
    final build = ++_builds;
    final repository = ref.watch(companyRepositoryProvider);
    if (!_started) {
      _started = true;
      final cached = repository.cachedCompanies();
      if (cached != null) {
        unawaited(
          Future<void>.delayed(Duration.zero, () async {
            if (ref.mounted) await _revalidate(repository, build);
          }),
        );
        return Future.value(cached);
      }
    }
    return _fetch(repository);
  }

  Future<List<Company>> _fetch(CompanyRepository repository) async {
    try {
      return await repository.listCompanies();
    } on Offline {
      // A start without network still names the active company, so the cached
      // feed can be shown. A Forbidden, NotFound or Unauthorized answer is a
      // server decision, not a network miss: never fall back to a company the
      // user may no longer be allowed to read.
      final cached = repository.cachedCompanies();
      if (cached != null) return cached;
      rethrow;
    } on TimedOut {
      final cached = repository.cachedCompanies();
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Replaces the cached list with the server's answer. A network miss keeps
  /// the cached list; any other error is the server's decision and replaces
  /// it, so a company the user lost access to does not stay on screen.
  Future<void> _revalidate(CompanyRepository repository, int build) async {
    try {
      final fresh = await repository.listCompanies();
      if (_isCurrent(repository, build)) state = AsyncData(fresh);
    } on Offline {
      // Keep the cached list.
    } on TimedOut {
      // Keep the cached list.
    } on Object catch (error, stack) {
      if (_isCurrent(repository, build)) state = AsyncError(error, stack);
    }
  }

  /// Whether a result still belongs to the build that started the request.
  ///
  /// A rebuild can happen while a revalidation is in flight: pull-to-refresh,
  /// or a new server after sign-out and sign-in within the timeout. The late
  /// answer belongs to the old build and must not replace newer state. The
  /// repository check also covers a notifier whose `ref` points at the current
  /// build after the provider was recreated.
  bool _isCurrent(CompanyRepository repository, int build) =>
      ref.mounted &&
      build == _builds &&
      identical(ref.read(companyRepositoryProvider), repository);
}

/// The companies the signed-in user can read.
final companiesProvider = AsyncNotifierProvider<Companies, List<Company>>(
  Companies.new,
);

/// Id of the company the user picked last, restored from preferences.
///
/// It may name a company that is gone; [activeCompanyProvider] falls back.
class ActiveCompanyId extends Notifier<String?> {
  @override
  String? build() => ref.read(appPrefsProvider).lastCompanyId;

  /// Makes [id] the company on screen and remembers it for the next start.
  Future<void> select(String id) async {
    state = id;
    await ref.read(appPrefsProvider).clearCachedFeed();
    await ref.read(appPrefsProvider).setLastCompanyId(id);
  }
}

/// The picked company id.
final activeCompanyIdProvider = NotifierProvider<ActiveCompanyId, String?>(
  ActiveCompanyId.new,
);

/// The company the Inbox shows: the last-used one if the user can still read
/// it, otherwise the first one, without an error (S3 AC3). Null while the
/// list has not loaded, or when it is empty.
final activeCompanyProvider = Provider<Company?>((ref) {
  final async = ref.watch(companiesProvider);
  // Riverpod keeps the previous list next to an error. A Forbidden or
  // NotFound answer means the server withdrew access: do not keep showing the
  // company it listed before.
  final error = async.error;
  if (error is Forbidden || error is NotFound) return null;
  final companies = async.value;
  if (companies == null || companies.isEmpty) return null;
  final id = ref.watch(activeCompanyIdProvider);
  return companies.firstWhere((c) => c.id == id, orElse: () => companies.first);
});
