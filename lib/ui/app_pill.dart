import 'package:flutter/material.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Color family of an [AppPill].
enum AppPillTone {
  /// Gray fill.
  neutral,

  /// Border only.
  outline,

  /// Accent on soft blue.
  blue,

  /// Warning: brown on amber.
  warn,

  /// Bad: red on soft red.
  bad,
}

/// Small rounded label, for example "Pending".
class AppPill extends StatelessWidget {
  /// Creates a pill.
  const new(
    this.label, {
    this.tone = AppPillTone.neutral,
    this.icon,
    super.key,
  });

  /// Text.
  final String label;

  /// Color family.
  final AppPillTone tone;

  /// Optional 13 px icon before the text.
  final AppIconName? icon;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final (Color fill, Color ink, Color? border) = switch (tone) {
      AppPillTone.neutral => (pp.panel, pp.ink2, null),
      AppPillTone.outline => (Colors.transparent, pp.ink2, pp.line),
      AppPillTone.blue => (pp.accentSoft, pp.accent, null),
      AppPillTone.warn => (pp.warnSoft, pp.warnInk, null),
      AppPillTone.bad => (pp.dangerSoft, pp.dangerInk, null),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AppIcon(icon!, size: 13, color: ink),
              const SizedBox(width: 4),
            ],
            Text(label, style: pp.text.microStrong.copyWith(color: ink)),
          ],
        ),
      ),
    );
  }
}
