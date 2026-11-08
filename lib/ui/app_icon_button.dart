import 'package:flutter/material.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Round 44×44 icon button for bars. [semanticLabel] is required because the
/// icon alone says nothing to a screen reader.
class AppIconButton extends StatefulWidget {
  /// Creates the button. A null [onPressed] disables it (40% opacity).
  const new({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.color,
    super.key,
  });

  /// Which icon.
  final AppIconName icon;

  /// Spoken label.
  final String semanticLabel;

  /// Called on tap. Null disables.
  final VoidCallback? onPressed;

  /// Icon color. Defaults to `ink`.
  final Color? color;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: Sizes.tap,
            height: Sizes.tap,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _pressed ? pp.panel : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: AppIcon(widget.icon, color: widget.color ?? pp.ink),
          ),
        ),
      ),
    );
  }
}
