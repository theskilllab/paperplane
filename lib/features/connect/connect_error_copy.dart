import 'package:flutter/foundation.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/core/error_presentation.dart';

/// Copy and guidance for one S1 failure.
@immutable
class ConnectError {
  /// Creates the error text.
  const new({required this.title, required this.message});

  /// Short headline.
  final String title;

  /// What the user can do next.
  final String message;
}

/// Maps an [ApiError] to S1 copy.
///
/// [host] is the address the user typed. [pasting] switches the 401 and 403
/// wording for "Paste token", where the credential is not a password.
ConnectError connectErrorFor(
  ApiError error, {
  String? host,
  bool pasting = false,
}) {
  final base = presentationFor(error, host: host);
  return switch (error) {
    Unauthorized() when pasting => const ConnectError(
      title: 'This key is not valid',
      message:
          'It may be expired or revoked. Create a new board key and try '
          'again.',
    ),
    Unauthorized() => const ConnectError(
      title: 'Email or password is wrong',
      message: 'Check the details for this server, then try again.',
    ),
    Forbidden() when pasting => const ConnectError(
      title: 'This key is not allowed',
      message: 'The server refused the key. Ask its admin for read access.',
    ),
    Forbidden() => const ConnectError(
      title: 'Key creation was refused',
      message:
          'The server did not allow this app to create a board key. Check '
          'that the address is allowed and that your account is a board user.',
    ),
    HostNotAllowed() => ConnectError(title: base.title, message: base.message),
    Redirected() => const ConnectError(
      title: 'Use the https:// address',
      message:
          'The server redirects requests. Enter its full https:// '
          'address instead.',
    ),
    NotFound() => const ConnectError(
      title: 'This is not a Paperclip server',
      message:
          'The address answered, but the sign-in endpoint is missing. '
          'Check the address.',
    ),
    _ => ConnectError(
      title: base.title,
      message: [base.message, ?base.detail].join(' '),
    ),
  };
}
