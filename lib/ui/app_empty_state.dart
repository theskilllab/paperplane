import 'package:flutter/material.dart';
import 'package:paperplane/ui/app_button.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Centered message for "nothing here" and "could not load" screens: icon,
/// title, text and an optional action.
class AppEmptyState extends StatelessWidget {
  /// Creates an empty state.
  const new({
    required this.title,
    this.icon = AppIconName.inbox,
    this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Creates the error variant: alert icon and a Retry button.
  const new error({
    required this.title,
    this.message,
    this.detail,
    this.actionLabel = 'Retry',
    this.onAction,
    super.key,
  }) : icon = AppIconName.alert;

  /// Icon above the title.
  final AppIconName icon;

  /// Headline.
  final String title;

  /// Text under the headline.
  final String? message;

  /// Small print, for example `Error 502`.
  final String? detail;

  /// Label of the action. Shown only with [onAction].
  final String? actionLabel;

  /// Called when the action is tapped.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 36, color: pp.ink3),
            const SizedBox(height: Space.s3),
            Text(title, textAlign: TextAlign.center, style: pp.text.emptyTitle),
            if (message != null) ...[
              const SizedBox(height: Space.s1),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: pp.text.small.copyWith(color: pp.ink3),
              ),
            ],
            if (detail != null) ...[
              const SizedBox(height: Space.s1),
              Text(detail!, textAlign: TextAlign.center, style: pp.text.micro),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: Space.s4),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                style: AppButtonStyle.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
