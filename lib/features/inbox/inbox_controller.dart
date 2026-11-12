import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show AsyncNotifierProviderFamily;
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/data/inbox_repository.dart';

/// What the Inbox of one company shows.
@immutable
class InboxData {
  /// Creates the data.
  const new({
    required this.feed,
    required this.agentNames,
    required this.fetchedAt,
  });

  /// The attention feed.
  final AttentionFeed feed;

  /// Agent id to name, for approval rows that carry only an id.
  final Map<String, String> agentNames;

  /// When the app got this feed ("Last updated").
  final DateTime fetchedAt;
}

/// Loads and refreshes the Inbox of one company.
///
/// - One provider per company, auto-disposed: switching company drops the old
///   company's feed, and an answer that arrives after the switch lands on a
///   disposed controller and is ignored (S3 AC6).
/// - At most one request runs at a time: [refresh] while one is in flight
///   does nothing (S2 AC2).
/// - A failed refresh keeps the data and adds the error, so the screen can
///   show "Last updated" with a banner (G2).
class InboxController extends AsyncNotifier<InboxData> {
  /// Creates the controller for [companyId].
  new(this.companyId);

  /// Company this controller serves.
  final String companyId;

  bool _busy = false;
  bool _started = false;
  Map<String, String> _agentNames = const {};

  @override
  Future<InboxData> build() async {
    final repo = ref.watch(inboxRepositoryProvider);
    if (!_started) {
      _started = true;
      final cached = repo.cachedFeed(companyId);
      if (cached != null) {
        // Show the last feed at once, then refresh behind it (PRD S1 AC11).
        // A failure keeps this data and adds the offline banner.
        unawaited(
          Future<void>.delayed(Duration.zero, () {
            if (ref.mounted) return refresh();
          }),
        );
        return InboxData(
          feed: cached.feed,
          agentNames: const {},
          fetchedAt: cached.savedAt,
        );
      }
    }
    _busy = true;
    try {
      final names = _agentNames.isNotEmpty
          ? Future.value(_agentNames)
          : _loadAgentNames(repo);
      final feed = await repo.fetchAttention(companyId);
      _agentNames = await names;
      return InboxData(
        feed: feed,
        agentNames: _agentNames,
        fetchedAt: ref.read(clockProvider)(),
      );
    } finally {
      _busy = false;
    }
  }

  /// Names are a nicety: a failure here must not hide the feed.
  Future<Map<String, String>> _loadAgentNames(InboxRepository repo) async {
    try {
      return await repo.agentNames(companyId);
    } on ApiError {
      return const {};
    }
  }

  /// Reloads the feed.
  ///
  /// With data on screen the rows stay until the answer arrives, and a failure
  /// keeps them next to the error (Riverpod carries the previous value through
  /// a rebuild). Without data (the first load failed) it starts over with the
  /// skeleton.
  ///
  /// [silent] is for the poll: it does nothing when there is no data, so a feed
  /// that cannot load is not retried every 30 s behind the user's back.
  Future<void> refresh({bool silent = false}) async {
    if (_busy || (silent && !state.hasValue)) return;
    ref.invalidateSelf();
    try {
      await future;
    } on Object {
      // The failure is in `state`; the screen shows it.
    }
  }
}

/// The Inbox of company `arg`.
final AsyncNotifierProviderFamily<InboxController, InboxData, String>
inboxProvider = AsyncNotifierProvider.autoDispose
    .family<InboxController, InboxData, String>(InboxController.new);
