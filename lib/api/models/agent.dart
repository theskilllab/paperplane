import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// An agent of a company (`GET /companies/{id}/agents`).
@immutable
class Agent {
  /// Creates an agent.
  const new({
    required this.id,
    required this.name,
    this.role = '',
    this.title,
    this.status,
  });

  /// Parses one entry tolerantly.
  factory fromJson(Map<String, Object?> json) => Agent(
    id: readString(json, 'id') ?? '',
    name: readString(json, 'name') ?? '',
    role: readString(json, 'role') ?? '',
    title: readNonEmpty(json, 'title'),
    status: readNonEmpty(json, 'status'),
  );

  /// Server id.
  final String id;

  /// Display name. Also the text of an `@mention`.
  final String name;

  /// Server role, for example `ceo`. Empty when the server sent none.
  final String role;

  /// Job title, when set.
  final String? title;

  /// Status such as `idle` or `terminated`, when sent.
  final String? status;

  /// True for the company's CEO (the default assignee in S7).
  bool get isCeo => role.toLowerCase() == 'ceo';

  /// Terminated agents cannot be assigned or mentioned.
  bool get isActive => status?.toLowerCase() != 'terminated';

  /// Parses a JSON array and drops entries without an id.
  static List<Agent> listFromJson(Object? json) => [
    for (final entry in asList(json))
      if (Agent.fromJson(asMap(entry)) case final a when a.id.isNotEmpty) a,
  ];

  /// The CEO among [agents], or null when there is none (S7 then defaults to
  /// "Unassigned").
  static Agent? ceoOf(Iterable<Agent> agents) {
    for (final agent in agents) {
      if (agent.isCeo && agent.isActive) return agent;
    }
    return null;
  }
}
