import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// A company (workspace) on the Paperclip instance.
@immutable
class Company {
  /// Creates a company.
  const new({required this.id, required this.name, this.issuePrefix});

  /// Parses `GET /companies` items. Missing fields read as empty.
  factory fromJson(Map<String, Object?> json) => Company(
    id: readString(json, 'id') ?? '',
    name: readString(json, 'name') ?? '',
    issuePrefix: readNonEmpty(json, 'issuePrefix'),
  );

  /// Server id.
  final String id;

  /// Display name.
  final String name;

  /// Prefix of issue identifiers, for example `ABC` in `ABC-12`.
  final String? issuePrefix;

  /// Parses a JSON array of companies and drops entries without an id.
  static List<Company> listFromJson(Object? json) => [
    for (final entry in asList(json))
      if (Company.fromJson(asMap(entry)) case final c when c.id.isNotEmpty) c,
  ];
}
