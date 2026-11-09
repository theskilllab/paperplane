import 'dart:async';

import 'package:flutter/material.dart';
import 'package:paperplane/ui/app_button.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Look of an [AppToast].
enum AppToastKind {
  /// Confirmation: ink background, check icon, 2.6 s.
  success,

  /// Failure: red background, alert icon, 5 s, usually with Retry.
  error,
}

/// The toast's visual. Use [showAppToast] to show one.
class AppToast extends StatelessWidget {
  /// Creates the toast content.
  const new({
    required this.message,
    this.kind = AppToastKind.success,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Text.
  final String message;

  /// Look.
  final AppToastKind kind;

  /// Optional action, for example `Retry` or `Open`.
  final String? actionLabel;

  /// Called when the action is tapped.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final error = kind == AppToastKind.error;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: error ? pp.danger : pp.ink,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                error ? AppIconName.alert : AppIconName.check,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: Space.s3),
              Flexible(
                child: Text(
                  message,
                  style: pp.text.small.copyWith(color: Colors.white),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: Space.s3),
                AppButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  style: AppButtonStyle.ghost,
                  small: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

OverlayEntry? _current;
Timer? _timer;

/// Shows a toast above the content and removes it after 2.6 s (5 s for
/// [AppToastKind.error]). A new toast replaces the one on screen.
///
/// Pass [overlay] when the toast must outlive [context], for example after the
/// screen that asked for it is gone.
void showAppToast(
  BuildContext context, {
  required String message,
  OverlayState? overlay,
  AppToastKind kind = AppToastKind.success,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final target = overlay ?? Overlay.of(context, rootOverlay: true);
  dismissAppToast();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: Space.s4,
      right: Space.s4,
      bottom: MediaQuery.paddingOf(context).bottom + Space.s5,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.column),
          child: AppToast(
            message: message,
            kind: kind,
            actionLabel: actionLabel,
            onAction: onAction == null
                ? null
                : () {
                    dismissAppToast();
                    onAction();
                  },
          ),
        ),
      ),
    ),
  );
  _current = entry;
  target.insert(entry);
  _timer = Timer(
    kind == AppToastKind.error
        ? const Duration(seconds: 5)
        : const Duration(milliseconds: 2600),
    dismissAppToast,
  );
}

/// Removes the toast on screen, if any.
void dismissAppToast() {
  _timer?.cancel();
  _timer = null;
  _current?.remove();
  _current = null;
}
