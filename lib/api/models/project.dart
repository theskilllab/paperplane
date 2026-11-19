import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// A project (`GET /companies/{id}/projects`).
@immutable
class Project {
  /// Creates a project.
  const new({required this.id, required this.name, this.archived = false});

  /// Parses one entry tolerantly.
  factory fromJson(Map<String, Object?> json) => Project(
    id: readString(json, 'id') ?? '',
    name: readString(json, 'name') ?? '',
    archived: readString(json, 'archivedAt') != null,
  );

  /// Server id.
  final String id;

  /// Display name.
  final String name;

  /// True when the server archived it.
  final bool archived;

  /// Parses a JSON array, dropping entries without an id or a name.
  static List<Project> listFromJson(Object? json) => [
    for (final entry in asList(json))
      if (Project.fromJson(asMap(entry)) case final p
          when p.id.isNotEmpty && p.name.isNotEmpty)
        p,
  ];
}
