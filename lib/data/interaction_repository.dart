import 'package:paperplane/api/api_client.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/json.dart';
import 'package:paperplane/api/models/interaction.dart';

/// One answer to one question, in the shape `POST .../respond` expects.
///
/// [optionIds] holds the selected choice ids. When a free-text option is
/// selected, [otherText] holds the typed answer.
class QuestionAnswer {
  /// Creates an answer.
  const new({
    required this.questionId,
    required this.optionIds,
    this.otherText,
  });

  /// Question id.
  final String questionId;

  /// Selected option ids.
  final List<String> optionIds;

  /// Typed answer for a free-text option.
  final String? otherText;

  /// Wire body.
  Map<String, Object?> toJson() => {
    'questionId': questionId,
    'optionIds': optionIds,
    if (otherText != null) 'otherText': otherText,
  };
}

/// Issue-thread interactions (S5).
///
/// There is no get-by-id endpoint: [find] re-reads the issue's whole list and
/// picks the interaction. The server is the authority on state, so every write
/// is followed by a fresh read of the list.
abstract interface class InteractionRepository {
  /// `GET /issues/{issueId}/interactions`.
  Future<List<Interaction>> list(String issueId);

  /// Re-reads the list and returns [interactionId], or null when it is gone.
  Future<Interaction?> find(String issueId, String interactionId);

  /// `POST .../respond` for an `ask_user_questions` interaction.
  Future<Interaction> respond(
    String issueId,
    String interactionId,
    List<QuestionAnswer> answers,
  );

  /// `POST .../accept`.
  Future<Interaction> accept(
    String issueId,
    String interactionId, {
    List<String> selectedClientKeys = const [],
    List<String> selectedOptionIds = const [],
    bool? rememberAction,
  });

  /// `POST .../reject` with an optional reason.
  Future<Interaction> reject(
    String issueId,
    String interactionId, {
    String? reason,
  });
}

/// [InteractionRepository] over HTTP.
class HttpInteractionRepository implements InteractionRepository {
  /// Creates the repository.
  const new(this._client);

  final ApiClient _client;

  /// Interactions answer 409 when they are already resolved or the issue is
  /// closed. A 422 is validation ("Select at least one suggested task") and
  /// must stay a [Server] error with its text (ADR 0001 §2).
  static const _alreadyHandled = {409};

  @override
  Future<List<Interaction>> list(String issueId) async {
    final response = await _client.get('/issues/$issueId/interactions');
    return [
      for (final entry in asList(response.data))
        Interaction.fromJson(asMap(entry)),
    ];
  }

  @override
  Future<Interaction?> find(String issueId, String interactionId) async {
    final interactions = await list(issueId);
    for (final interaction in interactions) {
      if (interaction.id == interactionId) return interaction;
    }
    return null;
  }

  @override
  Future<Interaction> respond(
    String issueId,
    String interactionId,
    List<QuestionAnswer> answers,
  ) => _write(issueId, interactionId, 'respond', {
    'answers': [for (final answer in answers) answer.toJson()],
  });

  @override
  Future<Interaction> accept(
    String issueId,
    String interactionId, {
    List<String> selectedClientKeys = const [],
    List<String> selectedOptionIds = const [],
    bool? rememberAction,
  }) => _write(issueId, interactionId, 'accept', {
    if (selectedClientKeys.isNotEmpty) 'selectedClientKeys': selectedClientKeys,
    if (selectedOptionIds.isNotEmpty) 'selectedOptionIds': selectedOptionIds,
    'rememberAction': ?rememberAction,
  });

  @override
  Future<Interaction> reject(
    String issueId,
    String interactionId, {
    String? reason,
  }) => _write(issueId, interactionId, 'reject', {
    if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
  });

  Future<Interaction> _write(
    String issueId,
    String interactionId,
    String action,
    Map<String, Object?> body,
  ) async {
    final response = await _client.post(
      '/issues/$issueId/interactions/$interactionId/$action',
      body: body,
      alreadyHandledStatuses: _alreadyHandled,
    );
    final json = asMap(response.data);
    final nested = asMap(json['interaction']);
    final parsed = Interaction.fromJson(nested.isEmpty ? json : nested);
    // Some server paths answer with a short receipt. Ask the list for the
    // canonical row instead of guessing what the write changed.
    if (parsed.id.isEmpty) {
      final current = await find(issueId, interactionId);
      if (current == null) throw const NotFound();
      return current;
    }
    return parsed;
  }
}
