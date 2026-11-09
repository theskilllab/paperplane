import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Agent avatar: a ghost with a stable two-color gradient per agent id.
///
/// Real data carries no colors, so the id is hashed into the 8 pairs the
/// prototype hard-codes per agent name.
class AppGhostAvatar extends StatelessWidget {
  /// Creates an avatar for the agent [agentId].
  const new(this.agentId, {this.size = 24, super.key});

  /// Agent id, hashed to pick the colors.
  final String agentId;

  /// Width and height. The spec uses 16, 20, 24, 28, 32, 40 and 56.
  final double size;

  static const _pairs = [
    ('#E8B84A', '#5C5FE6'),
    ('#CFE3DA', '#EE9F9F'),
    ('#5A32D4', '#46C2C0'),
    ('#D3E4D1', '#F1A3A3'),
    ('#F7E57A', '#F3CF48'),
    ('#6FC4B9', '#E57F7F'),
    ('#CFE3DA', '#EC9D9D'),
    ('#79C8BD', '#E47B7B'),
  ];

  /// Index into the color pairs for [id]. FNV-1a, so it is the same on every
  /// platform and run (`String.hashCode` is not guaranteed to be).
  static int pairIndex(String id) {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash % _pairs.length;
  }

  String get _svg {
    final (top, bottom) = _pairs[pairIndex(agentId)];
    return [
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">',
      '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">',
      '<stop offset="0" stop-color="$top"/>',
      '<stop offset="1" stop-color="$bottom"/></linearGradient></defs>',
      '<path d="M3 29V15a13 13 0 0 1 26 0v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" ',
      'fill="url(#g)"/>',
      '<circle cx="12" cy="17" r="1.3" fill="#2A2A33"/>',
      '<circle cx="20" cy="17" r="1.3" fill="#2A2A33"/>',
      '<path d="M13 21.5q3 2.6 6 0" fill="none" stroke="#2A2A33" ',
      'stroke-width="1.4" stroke-linecap="round"/></svg>',
    ].join();
  }

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    _svg,
    width: size,
    height: size,
    excludeFromSemantics: true,
  );
}

/// Avatar for a human author: a gray circle with initials.
class AppInitialsAvatar extends StatelessWidget {
  /// Creates an avatar for [name].
  const new(this.name, {this.size = 28, super.key});

  /// Full name. The first letters of up to two words are shown.
  final String name;

  /// Diameter.
  final double size;

  /// Up to two upper-case initials of [name]. `?` when it is empty.
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final letters = words.take(2).map((w) => w.substring(0, 1).toUpperCase());
    final joined = letters.join();
    return joined.isEmpty ? '?' : joined;
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: pp.panel, shape: BoxShape.circle),
      child: ExcludeSemantics(
        child: Text(
          initialsOf(name),
          style: pp.text.microStrong.copyWith(color: pp.ink2),
        ),
      ),
    );
  }
}
