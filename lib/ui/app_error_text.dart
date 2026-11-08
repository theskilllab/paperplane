import 'package:flutter/material.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Inline error: alert icon and red text, announced to screen readers when it
/// appears. Put it next to the control that failed, never on a button.
class AppErrorText extends StatelessWidget {
  /// Creates the error line.
  const new(this.message, {super.key});

  /// What went wrong, in plain words.
  final String message;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return Semantics(
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon(AppIconName.alert, size: 16, color: pp.danger),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(
              message,
              style: pp.text.small.copyWith(color: pp.danger),
            ),
          ),
        ],
      ),
    );
  }
}
