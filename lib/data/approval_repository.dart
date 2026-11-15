import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/json.dart';
import 'package:paperplane/api/models/approval.dart';

/// Detail and decisions of one approval (screen S4).
abstract interface class ApprovalRepository {
  /// `GET /approvals/{id}`.
  Future<Approval> fetch(String approvalId);

  /// `GET /approvals/{id}/issues`.
  Future<List<LinkedIssue>> linkedIssues(String approvalId);

  /// `POST /approvals/{id}/approve`, with an optional note.
  Future<Approval> approve(String approvalId, {String? decisionNote});

  /// `POST /approvals/{id}/reject`, with an optional note.
  Future<Approval> reject(String approvalId, {String? decisionNote});
}

/// [ApprovalRepository] over HTTP.
class HttpApprovalRepository implements ApprovalRepository {
  /// Creates the repository.
  const new(this._client);

  final ApiClient _client;

  /// Approvals answer 409 and 422 when the item is no longer pending.
  static const _alreadyHandled = {409, 422};

  @override
  Future<Approval> fetch(String approvalId) async {
    final response = await _client.get('/approvals/$approvalId');
    return Approval.fromJson(asMap(response.data));
  }

  @override
  Future<List<LinkedIssue>> linkedIssues(String approvalId) async {
    final response = await _client.get('/approvals/$approvalId/issues');
    return [
      for (final entry in asList(response.data))
        LinkedIssue.fromJson(asMap(entry)),
    ];
  }

  @override
  Future<Approval> approve(String approvalId, {String? decisionNote}) =>
      _decide('approve', approvalId, decisionNote);

  @override
  Future<Approval> reject(String approvalId, {String? decisionNote}) =>
      _decide('reject', approvalId, decisionNote);

  Future<Approval> _decide(
    String action,
    String approvalId,
    String? decisionNote,
  ) async {
    final note = decisionNote?.trim();
    final response = await _client.post(
      '/approvals/$approvalId/$action',
      body: {if (note != null && note.isNotEmpty) 'decisionNote': note},
      alreadyHandledStatuses: _alreadyHandled,
    );
    final body = asMap(response.data);
    final nested = asMap(body['approval']);
    final json = nested.isEmpty ? body : nested;
    // Some servers return only a short result. Re-read the item then.
    if (readNonEmpty(json, 'id') == null) return await fetch(approvalId);
    return Approval.fromJson(json);
  }
}
