/// Removes secrets from text before it reaches a log.
///
/// Board keys start with `pcp_board_`; the `Authorization` header holds one.
/// Request and response bodies are never logged at all, because sign-in
/// bodies carry passwords and `POST /board-api-keys` returns a fresh key.
abstract final class Redactor {
  static final _boardKey = RegExp(r'pcp_board_[A-Za-z0-9_\-.]*');
  static final _bearer = RegExp(r'(bearer\s+)[^\s,;]+', caseSensitive: false);

  /// Placeholder that replaces a secret.
  static const mask = '[redacted]';

  /// Returns [text] with board keys and bearer values masked.
  static String redact(String text) => text
      .replaceAll(_boardKey, mask)
      .replaceAllMapped(_bearer, (m) => '${m[1]}$mask');

  /// Returns [headers] with credentials masked, for logging.
  static Map<String, String> redactHeaders(Map<String, Object?> headers) {
    const sensitive = {'authorization', 'cookie', 'set-cookie'};
    return {
      for (final entry in headers.entries)
        entry.key: sensitive.contains(entry.key.toLowerCase())
            ? mask
            : redact('${entry.value}'),
    };
  }
}
