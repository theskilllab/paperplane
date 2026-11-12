import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/json.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/auth/app_prefs.dart';

/// A feed kept from an earlier run, for a cold start without network.
@immutable
class CachedFeed {
  /// Creates the value.
  const new({
    required this.companyId,
    required this.feed,
    required this.savedAt,
  });

  /// Company the feed belongs to.
  final String companyId;

  /// The parsed feed.
  final AttentionFeed feed;

  /// When the app fetched it.
  final DateTime savedAt;
}

/// Read side of the Inbox (screen S2). Approvals and interactions get their
/// own repositories in PR 2.
abstract interface class InboxRepository {
  /// First page of the attention feed, at most [limit] items (server max 100).
  Future<AttentionFeed> fetchAttention(String companyId, {int limit = 100});

  /// Last feed kept for [companyId], or null.
  CachedFeed? cachedFeed(String companyId);

  /// Agent id to display name, so approval rows can show who asked.
  ///
  /// PR 3 adds a full agent repository; this is the read-only slice PR 1 needs.
  Future<Map<String, String>> agentNames(String companyId);
}

/// [InboxRepository] over HTTP.
///
/// Sends `If-None-Match` and answers a 304 with the feed it already holds, so
/// a 30 s poll costs almost nothing when nothing changed.
class HttpInboxRepository implements InboxRepository {
  /// Creates the repository.
  new(this._client, {this.prefs, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ApiClient _client;

  /// Cache for a cold start without network. Null in tests.
  final AppPrefs? prefs;
  final DateTime Function() _now;
  final Map<String, ({String etag, AttentionFeed feed})> _cache = {};

  @override
  Future<AttentionFeed> fetchAttention(
    String companyId, {
    int limit = 100,
  }) async {
    final cached = _cache[companyId];
    final generation = prefs?.cacheGeneration;
    final response = await _client.get(
      '/companies/$companyId/attention',
      query: {'limit': limit},
      ifNoneMatch: cached?.etag,
      scope: companyId,
    );
    if (response.notModified && cached != null) return cached.feed;

    final feed = AttentionFeed.fromJson(asMap(response.data));
    final etag = response.etag;
    if (etag == null) {
      _cache.remove(companyId);
    } else {
      _cache[companyId] = (etag: etag, feed: feed);
    }
    // Keep the raw answer for the next cold start (PRD S1 AC11).
    await prefs?.setCachedFeed(
      companyId: companyId,
      json: jsonEncode(response.data),
      at: _now(),
      expectedGeneration: generation,
    );
    return feed;
  }

  @override
  CachedFeed? cachedFeed(String companyId) {
    final prefs = this.prefs;
    final raw = prefs?.cachedFeedJson;
    final savedAt = prefs?.cachedFeedAt;
    if (prefs == null ||
        raw == null ||
        savedAt == null ||
        prefs.cachedFeedCompanyId != companyId) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      return CachedFeed(
        companyId: companyId,
        feed: AttentionFeed.fromJson(asMap(json)),
        savedAt: savedAt,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<Map<String, String>> agentNames(String companyId) async {
    final response = await _client.get(
      '/companies/$companyId/agents',
      scope: companyId,
    );
    final names = <String, String>{};
    for (final entry in asList(response.data)) {
      final map = asMap(entry);
      if (readNonEmpty(map, 'id') case final id?) {
        names[id] = readNonEmpty(map, 'name') ?? '';
      }
    }
    return names;
  }
}
