import 'package:flutter/material.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Centers [child] in a column at most [maxWidth] wide (design spec §5).
///
/// iPad and Android tablets show the same single stack as a phone; this keeps
/// rows from stretching across the screen. Below [maxWidth] the child fills
/// the width.
class AppColumn extends StatelessWidget {
  /// Creates the column.
  const new({required this.child, this.maxWidth = Sizes.column, super.key});

  /// Widest the column gets.
  final double maxWidth;

  /// Content.
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
