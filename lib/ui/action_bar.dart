import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:paperplane/ui/app_column.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Sticky bottom bar with equal-width actions (design spec §2, `PpActionBar`).
///
/// A 1 px top line, the background at 94% with an 18 px blur, 12×16 padding
/// and the bottom safe area. Actions keep at least 44 pt height.
class AppActionBar extends StatelessWidget {
  /// Creates the bar.
  const new({required this.children, super.key})
    : assert(children.length > 0, 'An action bar needs at least one action.');

  /// Buttons, each given the same width.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: pp.bg.withValues(alpha: 0.94),
            border: Border(top: BorderSide(color: pp.line)),
          ),
          child: SafeArea(
            top: false,
            child: AppColumn(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s4,
                  vertical: Space.s3,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(width: Space.s3),
                      Expanded(child: children[i]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
