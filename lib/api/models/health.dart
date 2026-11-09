import 'package:flutter/foundation.dart';
import 'package:paperplane/api/json.dart';

/// How the instance authenticates people.
enum DeploymentMode {
  /// Accounts and sessions. The only mode Paperplane supports.
  authenticated,

  /// No accounts at all (local single-user). Not supported.
  localTrusted,

  /// A value this app does not know.
  unknown;

  /// Parses the wire value tolerantly.
  static DeploymentMode parse(String? value) => switch (value) {
    'authenticated' => authenticated,
    'local_trusted' => localTrusted,
    _ => unknown,
  };
}

/// Answer of `GET /health` (no auth).
@immutable
class HealthInfo {
  /// Creates the value.
  const new({
    required this.status,
    required this.mode,
    this.exposure,
    this.version,
  });

  /// Parses the body tolerantly.
  factory fromJson(Map<String, Object?> json) => HealthInfo(
    status: readString(json, 'status') ?? '',
    mode: DeploymentMode.parse(readString(json, 'deploymentMode')),
    exposure: readNonEmpty(json, 'deploymentExposure'),
    version: readNonEmpty(json, 'version'),
  );

  /// Server status text, `ok` when healthy.
  final String status;

  /// Authentication mode.
  final DeploymentMode mode;

  /// `private` or `public`, when the server says.
  final String? exposure;

  /// Server version. Null without auth.
  final String? version;

  /// True when the body looks like a Paperclip health answer.
  bool get isHealthy => status == 'ok';
}
