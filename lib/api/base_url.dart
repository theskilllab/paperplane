/// Result of parsing what the user typed as the server address.
sealed class BaseUrlResult {
  const new();
}

/// A usable server address.
final class BaseUrlOk extends BaseUrlResult {
  /// Creates a result for [uri]. [encrypted] is false for plain `http`.
  const new(this.uri, {required this.encrypted});

  /// Normalised address: scheme and host lower-case, no query, no fragment,
  /// no trailing slash.
  final Uri uri;

  /// False for `http`. Show the "Not encrypted" banner (PRD S1).
  final bool encrypted;

  /// Stable key for per-instance storage.
  String get key => uri.toString();
}

/// Why an address is rejected.
enum BaseUrlProblem {
  /// Nothing typed.
  empty,

  /// Not a URL with a host, or a scheme other than http and https.
  invalid,

  /// Plain `http` to a host that is not a private or local address.
  insecurePublicHost,
}

/// An address the app refuses.
final class BaseUrlRejected extends BaseUrlResult {
  /// Creates the result.
  const new(this.problem);

  /// Reason, for the form's error text.
  final BaseUrlProblem problem;
}

/// Parses the server address and applies the transport policy.
///
/// The policy looks at the **host string only**. The app cannot know what a
/// name resolves to, so a DNS name that points at a private IP must use HTTPS
/// (or the IP itself). Plain `http` is allowed for RFC 1918 and `100.64.0.0/10`
/// IP literals, loopback, `.local`, `.ts.net` and single-label names.
abstract final class BaseUrl {
  /// Parses [input]. A missing scheme is treated as invalid on purpose, so the
  /// user sees "Include https://".
  static BaseUrlResult parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return const BaseUrlRejected(BaseUrlProblem.empty);

    final parsed = Uri.tryParse(text);
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty) {
      return const BaseUrlRejected(BaseUrlProblem.invalid);
    }
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      return const BaseUrlRejected(BaseUrlProblem.invalid);
    }

    final host = parsed.host.toLowerCase();
    final encrypted = scheme == 'https';
    if (!encrypted && !isPrivateHost(host)) {
      return const BaseUrlRejected(BaseUrlProblem.insecurePublicHost);
    }

    var path = parsed.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final uri = Uri(
      scheme: scheme,
      host: host,
      port: parsed.hasPort ? parsed.port : null,
      path: path,
    );
    return BaseUrlOk(uri, encrypted: encrypted);
  }

  /// Whether plain `http` is acceptable for [host] (already lower-case).
  static bool isPrivateHost(String host) {
    final ip = _ipv4(host);
    if (ip != null) {
      final [a, b, ...] = ip;
      return a == 10 ||
          a == 127 ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 100 && b >= 64 && b <= 127);
    }
    if (host == 'localhost' || host == '::1' || host == '[::1]') return true;
    if (host.endsWith('.local') || host.endsWith('.ts.net')) return true;
    return !host.contains('.') && !host.contains(':');
  }

  static List<int>? _ipv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return null;
      numbers.add(n);
    }
    return numbers;
  }
}
