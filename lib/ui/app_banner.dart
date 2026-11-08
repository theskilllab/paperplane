import 'package:flutter/material.dart';
import 'package:paperplane/ui/app_button.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Kind of an [AppBanner].
enum AppBannerKind {
  /// Neutral information (soft blue).
  info,

  /// Something to watch, for example plain HTTP (amber).
  warn,

  /// Something failed (soft red).
  error,

  /// The server cannot be reached; data on screen may be old (amber).
  offline,
}

/// Inline message strip with an icon, a bold title, text and an optional
/// action such as Retry. Error and offline banners are announced to screen
/// readers when they appear.
class AppBanner extends StatelessWidget {
  /// Creates a banner.
  const new({
    required this.kind,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Kind, which sets colors and icon.
  final AppBannerKind kind;

  /// Bold first line.
  final String title;

  /// Optional text under the title.
  final String? message;

  /// Label of the action button. Shown only with [onAction].
  final String? actionLabel;

  /// Called when the action is tapped.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final (Color fill, Color ink, AppIconName icon) = switch (kind) {
      AppBannerKind.info => (pp.accentSoft, pp.accent, AppIconName.alert),
      AppBannerKind.warn => (pp.warnSoft, pp.warnInk, AppIconName.alert),
      AppBannerKind.error => (pp.dangerSoft, pp.dangerInk, AppIconName.alert),
      AppBannerKind.offline => (pp.warnSoft, pp.warnInk, AppIconName.alert),
    };
    final live = kind == AppBannerKind.error || kind == AppBannerKind.offline;
    return Semantics(
      container: true,
      liveRegion: live,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AppIcon(icon, size: 18, color: ink),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: pp.text.smallStrong.copyWith(color: ink),
                    ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          message!,
                          style: pp.text.small.copyWith(color: ink),
                        ),
                      ),
                    if (onAction != null && actionLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s2),
                        child: AppButton(
                          label: actionLabel!,
                          onPressed: onAction,
                          style: AppButtonStyle.secondary,
                          small: true,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
