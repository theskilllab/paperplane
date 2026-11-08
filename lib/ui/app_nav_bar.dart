import 'package:flutter/material.dart';
import 'package:paperplane/ui/app_column.dart';
import 'package:paperplane/ui/app_icon_button.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Top bar: back on the left, a centered upper-case title, actions on the
/// right. A root screen can add a large title under the bar.
///
/// On tablets the content stays inside the 640 pt column while the background
/// spans the screen (design spec §5). Use as `Scaffold.appBar`.
class AppNavBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the bar.
  const new({
    this.title,
    this.largeTitle,
    this.onBack,
    this.leading,
    this.actions = const [],
    this.scrolled = false,
    super.key,
  });

  /// Small centered title, shown in upper case (for example an issue id).
  final String? title;

  /// Large left-aligned title for root screens.
  final String? largeTitle;

  /// Shows a back button that calls this.
  final VoidCallback? onBack;

  /// Replaces the back button.
  final Widget? leading;

  /// Widgets on the right, for example `AppIconButton`s.
  final List<Widget> actions;

  /// True after the content scrolled: the bar gets its translucent fill and a
  /// hairline.
  final bool scrolled;

  static const double _largeTitleHeight = 48;

  @override
  Size get preferredSize => Size.fromHeight(
    Sizes.barH + (largeTitle == null ? 0 : _largeTitleHeight),
  );

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final lead =
        leading ??
        (onBack == null
            ? null
            : AppIconButton(
                icon: AppIconName.back,
                semanticLabel: 'Back',
                onPressed: onBack,
                color: pp.accent,
              ));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scrolled ? pp.barScrolled : pp.bg,
        border: scrolled ? Border(bottom: BorderSide(color: pp.line)) : null,
      ),
      child: SafeArea(
        bottom: false,
        child: AppColumn(
          child: ClampedTextScale(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: Sizes.barH,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: lead,
                          ),
                        ),
                        if (title != null)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Semantics(
                              header: true,
                              child: Text(
                                title!.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: pp.text.barTitle,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (largeTitle != null)
                  SizedBox(
                    height: _largeTitleHeight,
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                      child: Semantics(
                        header: true,
                        child: Text(
                          largeTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: pp.text.largeTitle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
