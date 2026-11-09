import 'package:flutter/material.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Visual emphasis of an [AppButton].
enum AppButtonStyle {
  /// Main action on a screen: ink fill, white text.
  primary,

  /// Lower-emphasis action: border only.
  secondary,

  /// Destructive action: red fill, white text.
  danger,

  /// Text-only action in the accent color.
  ghost,
}

/// A button with a solid surface.
///
/// States follow the design spec: pressed (scale 0.97, opacity 0.85),
/// disabled (gray), and loading (spinner replaces the label, width kept,
/// taps ignored). Errors are never shown on the button; put an `AppErrorText`
/// next to it.
class AppButton extends StatefulWidget {
  /// Creates a button. A null [onPressed] disables it.
  const new({
    required this.label,
    required this.onPressed,
    this.style = AppButtonStyle.primary,
    this.small = false,
    this.block = false,
    this.loading = false,
    this.loadingLabel,
    super.key,
  });

  /// Text shown on the button.
  final String label;

  /// Called when the button is tapped. Null disables the button.
  final VoidCallback? onPressed;

  /// Emphasis of the button.
  final AppButtonStyle style;

  /// 44 high instead of 48, with less padding.
  final bool small;

  /// Fill the available width.
  final bool block;

  /// Show a spinner instead of the label and ignore taps.
  final bool loading;

  /// Spoken while [loading], for example "Approving…". Defaults to [label].
  final String? loadingLabel;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final enabled = _enabled;
    final disabled = widget.onPressed == null && !widget.loading;

    final (
      Color fill,
      Color foreground,
      Color? border,
    ) = switch (widget.style) {
      _ when disabled => (pp.panel, pp.ink3, null),
      AppButtonStyle.primary => (
        _hovered ? pp.inkHover : pp.ink,
        Colors.white,
        null,
      ),
      AppButtonStyle.secondary => (pp.bg, pp.ink, pp.line),
      AppButtonStyle.danger => (pp.danger, Colors.white, null),
      AppButtonStyle.ghost => (Colors.transparent, pp.accent, null),
    };

    final label = Text(
      widget.label,
      style: pp.text.button.copyWith(color: foreground),
      textAlign: TextAlign.center,
    );
    final content = widget.loading
        ? Stack(
            alignment: Alignment.center,
            children: [
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: label,
              ),
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: foreground,
                ),
              ),
            ],
          )
        : label;

    final height = widget.small ? Sizes.tap : Sizes.tapLg;
    final button = AnimatedScale(
      scale: _pressed && enabled ? 0.97 : 1,
      duration: Motion.of(context, Motion.fast),
      child: AnimatedOpacity(
        opacity: _pressed && enabled ? 0.85 : 1,
        duration: Motion.of(context, Motion.fast),
        child: Container(
          constraints: BoxConstraints(minHeight: height, minWidth: 44),
          padding: EdgeInsets.symmetric(horizontal: widget.small ? 16 : 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(Radii.md),
            border: border == null ? null : Border.all(color: border),
          ),
          foregroundDecoration: _focused
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: pp.accent, width: 3),
                )
              : null,
          child: content,
        ),
      ),
    );

    return ClampedTextScale(
      child: Semantics(
        button: true,
        enabled: enabled || widget.loading,
        label: widget.loading ? (widget.loadingLabel ?? widget.label) : null,
        excludeSemantics: widget.loading,
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onShowHoverHighlight: (v) => setState(() => _hovered = v),
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // All four handlers are null when disabled: any tap handler would
            // make a disabled button announce a tap action to screen readers.
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapCancel: enabled
                ? () => setState(() => _pressed = false)
                : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTap: enabled ? widget.onPressed : null,
            child: widget.block
                ? SizedBox(width: double.infinity, child: button)
                : button,
          ),
        ),
      ),
    );
  }
}
