/// Tolerant JSON readers.
///
/// The server's OpenAPI document has almost no response types, so models are
/// parsed by hand and never throw on a missing or oddly typed field. A field
/// that is absent reads as null or a safe default.
library;

/// Returns [value] as a map, or an empty map.
Map<String, Object?> asMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

/// Returns [value] as a list, or an empty list.
List<Object?> asList(Object? value) => value is List ? value : const [];

/// Reads a string field, or null.
String? readString(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

/// Reads a non-empty string field, or null.
String? readNonEmpty(Map<String, Object?> json, String key) {
  final value = readString(json, key);
  return value == null || value.isEmpty ? null : value;
}

/// Reads an integer field, or [fallback].
int readInt(Map<String, Object?> json, String key, {int fallback = 0}) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

/// Reads a boolean field, or [fallback].
bool readBool(Map<String, Object?> json, String key, {bool fallback = false}) {
  final value = json[key];
  return value is bool ? value : fallback;
}

/// Reads an ISO-8601 date field, or null.
DateTime? readDate(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? DateTime.tryParse(value) : null;
}
