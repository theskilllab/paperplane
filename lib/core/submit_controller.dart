import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';

/// State of one write action (sign in, approve, send, create).
@immutable
sealed class SubmitState<T> {
  const new();

  /// True while a request is in flight. Disable the controls (PRD G6).
  bool get isSubmitting => this is SubmitInFlight<T>;
}

/// Nothing has been sent, or the screen reset the state.
final class SubmitIdle<T> extends SubmitState<T> {
  /// Creates the state.
  const new();
}

/// A request is running.
final class SubmitInFlight<T> extends SubmitState<T> {
  /// Creates the state.
  const new();
}

/// The request succeeded with [value].
final class SubmitSuccess<T> extends SubmitState<T> {
  /// Creates the state.
  const new(this.value);

  /// Result of the action.
  final T value;
}

/// The request failed. The screen keeps what the user typed and shows
/// [error] inline.
final class SubmitFailure<T> extends SubmitState<T> {
  /// Creates the state.
  const new(this.error);

  /// What went wrong.
  final ApiError error;
}

/// The server says the item changed (409 or 422). The controller already
/// re-fetched; show "Already handled" with the current state (PRD G10).
final class SubmitAlreadyHandled<T> extends SubmitState<T> {
  /// Creates the state.
  const new();
}

/// Runs a write action once at a time and reports its state.
///
/// - One tap, one request: a call while one is in flight is ignored (G6).
/// - Failure never clears input; the controller does not own any.
/// - [AlreadyHandled] triggers [submit]'s `onAlreadyHandled` re-fetch (G10).
///
/// Declare one provider per action:
/// ```dart
/// final approveProvider = NotifierProvider.autoDispose<
///     SubmitController<void>, SubmitState<void>>(SubmitController.new);
/// ```
class SubmitController<T> extends Notifier<SubmitState<T>> {
  @override
  SubmitState<T> build() => SubmitIdle<T>();

  /// Runs [action]. Returns false, without running it, if a request is
  /// already in flight.
  ///
  /// [onAlreadyHandled] runs when [action] throws [AlreadyHandled]; use it to
  /// re-fetch the item and refresh the Inbox. Any other [ApiError] becomes
  /// [SubmitFailure]. Anything that is not an [ApiError] is a bug: the state
  /// becomes [SubmitFailure] with [Unexpected] and the error is rethrown.
  Future<bool> submit(
    Future<T> Function() action, {
    Future<void> Function()? onAlreadyHandled,
  }) async {
    if (state.isSubmitting) return false;
    state = SubmitInFlight<T>();
    try {
      final value = await action();
      if (ref.mounted) state = SubmitSuccess<T>(value);
      return true;
    } on AlreadyHandled {
      try {
        await onAlreadyHandled?.call();
      } on ApiError {
        // The refresh failed too. The caller's own refresh state reports it.
      }
      if (ref.mounted) state = SubmitAlreadyHandled<T>();
      return true;
    } on ApiError catch (error) {
      if (ref.mounted) state = SubmitFailure<T>(error);
      return true;
    } on Object {
      // A bug, not a server answer. Do not leave the button stuck in flight;
      // show the generic failure and let the error reach the error zone.
      if (ref.mounted) state = SubmitFailure<T>(const Unexpected());
      rethrow;
    }
  }

  /// Returns to idle, for example when the user edits the input again.
  void reset() {
    if (!state.isSubmitting) state = SubmitIdle<T>();
  }
}
