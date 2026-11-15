import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/session_controller.dart';

/// The companies the signed-in user can read.
///
/// Reloaded on pull-to-refresh and when the switcher opens. While a reload
/// runs, or after it failed, the previous list stays available (S3 AC4).
final companiesProvider = FutureProvider<List<Company>>((ref) async {
  final repository = ref.watch(companyRepositoryProvider);
  try {
    return await repository.listCompanies();
  } on Offline {
    // A cold start without network still names the active company, so the
    // cached feed can be shown (PRD S1 AC11). A Forbidden, NotFound or
    // Unauthorized answer is a server decision, not a network miss: never
    // fall back to a company the user may no longer be allowed to read.
    final cached = repository.cachedCompanies();
    if (cached != null) return cached;
    rethrow;
  } on TimedOut {
    final cached = repository.cachedCompanies();
    if (cached != null) return cached;
    rethrow;
  }
});

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
  final companies = ref.watch(companiesProvider).value;
  if (companies == null || companies.isEmpty) return null;
  final id = ref.watch(activeCompanyIdProvider);
  return companies.firstWhere((c) => c.id == id, orElse: () => companies.first);
});
