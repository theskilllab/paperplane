import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/core/error_presentation.dart';
import 'package:paperplane/ui/app_banner.dart';
import 'package:paperplane/ui/app_empty_state.dart';
import 'package:paperplane/ui/app_skeleton_row.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Renders an `AsyncValue` the same way on every screen.
///
/// - First load, no data: skeleton rows (G1).
/// - Error, no data, offline or 5xx: error state with Retry (G2, G5).
/// - Error, no data, 403: "You don't have access to this" and Back, with no
///   retry loop (G4).
/// - Error, no data, 401: "Your session expired" while the router moves to
///   S1 (G3).
/// - Data, then an error: the old data plus a banner with "Last updated"
///   (G2).
/// - Data, empty: [empty].
///
/// It must sit where it can take the full height (a screen body), because the
/// banner and the content share a column.
class AsyncStateView<T> extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.value,
    required this.builder,
    this.onRetry,
    this.onBack,
    this.isEmpty,
    this.empty,
    this.host,
    this.lastUpdated,
    this.skeletonRows = 3,
    super.key,
  });

  /// The state to render.
  final AsyncValue<T> value;

  /// Builds the content from loaded data.
  final Widget Function(BuildContext context, T data) builder;

  /// Called by Retry buttons. Without it, no Retry is shown.
  final VoidCallback? onRetry;

  /// Called by the Back button of the no-access state.
  final VoidCallback? onBack;

  /// Tells whether loaded data counts as empty.
  final bool Function(T data)? isEmpty;

  /// Shown when [isEmpty] says so. Defaults to a generic message.
  final Widget? empty;

  /// Server name for "Can't reach {host}".
  final String? host;

  /// When the data on screen was fetched, for "Last updated".
  final DateTime? lastUpdated;

  /// Number of skeleton rows while loading.
  final int skeletonRows;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) {
      final data = value.requireValue;
      final body = (isEmpty?.call(data) ?? false)
          ? (empty ?? const AppEmptyState(title: 'Nothing here'))
          : builder(context, data);
      final error = value.hasError ? value.error : null;
      if (error is! ApiError) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s2,
              Space.s4,
              Space.s2,
            ),
            child: _staleBanner(error),
          ),
          Expanded(child: body),
        ],
      );
    }

    final error = value.error;
    if (value.hasError && error is ApiError) return _errorState(error);
    if (value.hasError) {
      return AppEmptyState.error(
        title: 'Something went wrong',
        onAction: onRetry,
      );
    }
    return _skeleton();
  }

  Widget _skeleton() => Semantics(
    label: 'Loading',
    liveRegion: true,
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Space.s4),
      children: [
        for (var i = 0; i < skeletonRows; i++) ...[
          if (i > 0) const SizedBox(height: Space.s2),
          const AppSkeletonRow(),
        ],
      ],
    ),
  );

  Widget _staleBanner(ApiError error) {
    final p = presentationFor(error, host: host);
    final stamp = lastUpdated == null
        ? null
        : 'Last updated ${formatClock(lastUpdated!)}';
    return switch (p.kind) {
      ErrorKind.offline => AppBanner(
        kind: AppBannerKind.offline,
        title: p.title,
        message: stamp ?? p.message,
        actionLabel: onRetry == null ? null : 'Retry',
        onAction: onRetry,
      ),
      _ => AppBanner(
        kind: AppBannerKind.error,
        title: p.title,
        message: [p.message, ?stamp].join(' '),
        actionLabel: p.retryable && onRetry != null ? 'Retry' : null,
        onAction: p.retryable ? onRetry : null,
      ),
    };
  }

  Widget _errorState(ApiError error) {
    final p = presentationFor(error, host: host);
    return switch (p.kind) {
      ErrorKind.noAccess => AppEmptyState(
        icon: AppIconName.shield,
        title: p.title,
        message: p.message,
        actionLabel: 'Back',
        onAction: onBack,
      ),
      ErrorKind.sessionExpired => AppEmptyState(
        icon: AppIconName.alert,
        title: p.title,
        message: p.message,
      ),
      _ => AppEmptyState.error(
        title: p.title,
        message: p.message,
        detail: p.detail,
        onAction: p.retryable ? onRetry : null,
      ),
    };
  }
}

/// Formats [time] as local `HH:mm`.
String formatClock(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
