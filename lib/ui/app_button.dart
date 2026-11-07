import 'package:flutter/material.dart';

/// Visual emphasis of an [AppButton].
enum AppButtonStyle {
  /// Main action on a screen.
  primary,

  /// Lower-emphasis action.
  secondary,
}

/// A button with a solid surface.
class AppButton extends StatelessWidget {
  /// Creates a button. A null [onPressed] disables it.
  const new({
    required this.label,
    required this.onPressed,
    this.style = AppButtonStyle.primary,
    super.key,
  });

  /// Text shown on the button.
  final String label;

  /// Called when the button is tapped. Null disables the button.
  final VoidCallback? onPressed;

  /// Emphasis of the button.
  final AppButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final text = Text(label);
    return switch (style) {
      AppButtonStyle.primary => FilledButton(onPressed: onPressed, child: text),
      AppButtonStyle.secondary => OutlinedButton(
        onPressed: onPressed,
        child: text,
      ),
    };
  }
}
