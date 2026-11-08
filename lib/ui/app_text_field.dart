import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:paperplane/ui/app_error_text.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Text field with the label above, help text and error text below.
///
/// 48 high, 10 radius, 1 px `line` border, 2 px `accent` border when focused.
/// [loading] shows a small spinner at the end (for example while a URL is
/// being checked). Errors show as `AppErrorText`; the field keeps its text.
class AppTextField extends StatelessWidget {
  /// Creates the field.
  const new({
    required this.label,
    this.controller,
    this.focusNode,
    this.help,
    this.errorText,
    this.required = false,
    this.enabled = true,
    this.loading = false,
    this.obscureText = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  /// Label above the field. Also the accessibility label.
  final String label;

  /// Text controller.
  final TextEditingController? controller;

  /// Focus node.
  final FocusNode? focusNode;

  /// Help text below the field.
  final String? help;

  /// Error text below the field. Replaces [help].
  final String? errorText;

  /// Adds a red `*` to the label.
  final bool required;

  /// False shows the disabled surface.
  final bool enabled;

  /// Shows a trailing spinner.
  final bool loading;

  /// Hides the text (passwords).
  final bool obscureText;

  /// Focus on first build.
  final bool autofocus;

  /// Lines before scrolling. Null grows without limit.
  final int? maxLines;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Action key on the keyboard.
  final TextInputAction? textInputAction;

  /// Autofill hints.
  final Iterable<String>? autofillHints;

  /// Input formatters.
  final List<TextInputFormatter>? inputFormatters;

  /// Called on each change.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final hasError = errorText != null && errorText!.isNotEmpty;

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      borderSide: BorderSide(color: color, width: width),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: pp.text.smallStrong,
            children: [
              if (required)
                TextSpan(
                  text: ' *',
                  style: pp.text.smallStrong.copyWith(color: pp.danger),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s1 + 2),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.tapLg),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            obscureText: obscureText,
            autofocus: autofocus,
            maxLines: obscureText ? 1 : maxLines,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: pp.text.body,
            cursorColor: pp.accent,
            decoration: InputDecoration(
              isDense: true,
              filled: !enabled,
              fillColor: pp.panel,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Space.s3,
                vertical: 14,
              ),
              border: border(hasError ? pp.danger : pp.line, 1),
              enabledBorder: border(hasError ? pp.danger : pp.line, 1),
              disabledBorder: border(pp.line, 1),
              focusedBorder: border(hasError ? pp.danger : pp.accent, 2),
              suffixIcon: loading
                  ? const Padding(
                      padding: EdgeInsets.all(Space.s3),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : null,
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: Space.s1 + 2),
          AppErrorText(errorText!),
        ] else if (help != null) ...[
          const SizedBox(height: Space.s1 + 2),
          Text(help!, style: pp.text.small.copyWith(color: pp.ink3)),
        ],
      ],
    );
  }
}
