import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// The 16 icons Paperplane P0 uses (design spec §2, "Icons").
///
/// One stroke family: 24×24 grid, stroke 1.9, round caps and joins, drawn in
/// `currentColor`. The paths are original drawings in the prototype's style;
/// they are not copied from an icon pack. Add an icon only when a screen
/// needs it.
enum AppIconName {
  /// Back arrow.
  back(['<path d="M15 5l-7 7 7 7"/>']),

  /// Chevron right.
  chev(['<path d="M9 5l7 7-7 7"/>']),

  /// Plus.
  plus(['<path d="M12 5v14M5 12h14"/>']),

  /// Check mark.
  check(['<path d="M5 12.5l4.5 4.5L19 7.5"/>']),

  /// Cross.
  x(['<path d="M6 6l12 12M18 6L6 18"/>']),

  /// Alert circle.
  alert([
    '<circle cx="12" cy="12" r="9"/>',
    '<path d="M12 7.5v5.5"/>',
    '<path d="M12 16.6h.01"/>',
  ]),

  /// Send (arrow up).
  send(['<path d="M12 19V5M5 12l7-7 7 7"/>']),

  /// Inbox tray.
  inbox([
    '<path d="M4 13l2.4-7.2A2 2 0 0 1 8.3 4.4h7.4a2 2 0 0 1 1.9 1.4L20 13v5',
    'a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/>',
    '<path d="M4 13h4.4a1 1 0 0 1 1 1 2.6 2.6 0 0 0 5.2 0 1 1 0 0 1 1-1H20"/>',
  ]),

  /// Shield.
  shield(['<path d="M12 3l7 3v5.5c0 4.4-3 7.9-7 9.5-4-1.6-7-5.1-7-9.5V6z"/>']),

  /// Person with a plus (join request).
  userplus([
    '<circle cx="10" cy="8" r="4"/>',
    '<path d="M3 20c0-3.3 3.1-6 7-6s7 2.7 7 6"/>',
    '<path d="M19 8v6M16 11h6"/>',
  ]),

  /// Paper plane (the app mark).
  plane(['<path d="M21 3L3 10.5l7 3 3 7z"/>', '<path d="M21 3l-11 10.5"/>']),

  /// Server.
  server([
    '<rect x="4" y="4" width="16" height="7" rx="1.5"/>',
    '<rect x="4" y="13" width="16" height="7" rx="1.5"/>',
    '<path d="M8 7.5h.01M8 16.5h.01"/>',
  ]),

  /// Swap (two arrows).
  swap(['<path d="M7 4L3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7"/>']),

  /// Folder.
  folder([
    '<path d="M3 7a2 2 0 0 1 2-2h4l2 2.5h8a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H5',
    'a2 2 0 0 1-2-2z"/>',
  ]),

  /// Two people.
  agents([
    '<circle cx="9" cy="8" r="3.5"/>',
    '<path d="M2.5 20c0-3 2.9-5.2 6.5-5.2s6.5 2.2 6.5 5.2"/>',
    '<path d="M16 4.6a3.5 3.5 0 0 1 0 6.4M18 14.9c2 .6 3.5 2.2 3.5 4.6"/>',
  ]),

  /// Link.
  link([
    '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/>',
    '<path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
  ]);

  new(this._parts);

  final List<String> _parts;

  /// Full SVG document, drawn in `currentColor`.
  String get svg =>
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none" stroke="currentColor" stroke-width="1.9" '
      'stroke-linecap="round" stroke-linejoin="round">${_parts.join()}</svg>';
}

/// Draws an [AppIconName] in the ambient icon color.
class AppIcon extends StatelessWidget {
  /// Creates an icon. It is decorative unless [semanticLabel] is set.
  const new(
    this.name, {
    this.size = 22,
    this.color,
    this.semanticLabel,
    super.key,
  });

  /// Which icon.
  final AppIconName name;

  /// Width and height.
  final double size;

  /// Stroke color. Defaults to the ambient icon color, then `ink`.
  final Color? color;

  /// Spoken label. Null hides the icon from screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? context.pp.ink;
    return SvgPicture.string(
      name.svg,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: resolved),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
