import 'package:flutter/material.dart';
import 'package:paperplane/ui/app_column.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// The reply bar at the bottom of a thread: an optional [leading] button, a
/// growing text field and a round send button.
///
/// The field takes text from the system keyboard, so iOS dictation works
/// without custom code. [onSend] null disables the send button (empty text, or
/// a send in flight).
class AppComposer extends StatelessWidget {
  /// Creates the bar.
  const new({
    required this.controller,
    required this.onSend,
    this.focusNode,
    this.leading,
    this.hint = 'Reply',
    this.sendLabel = 'Send reply',
    this.maxLines = 5,
    super.key,
  });

  /// Text of the field.
  final TextEditingController controller;

  /// Focus of the field.
  final FocusNode? focusNode;

  /// Called by the send button. Null disables it.
  final VoidCallback? onSend;

  /// Button before the field, for example the @agent button.
  final Widget? leading;

  /// Placeholder text.
  final String hint;

  /// Spoken label of the send button.
  final String sendLabel;

  /// Lines before the field scrolls.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final enabled = onSend != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pp.bg,
        border: Border(top: BorderSide(color: pp.line)),
      ),
      child: SafeArea(
        top: false,
        child: AppColumn(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s2,
              Space.s2,
              Space.s2,
              Space.s2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ?leading,
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: pp.panel,
                      borderRadius: BorderRadius.circular(Radii.composer),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: Sizes.tap),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 1,
                        maxLines: maxLines,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textCapitalization: TextCapitalization.sentences,
                        style: pp.text.body,
                        cursorColor: pp.accent,
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: pp.text.body.copyWith(color: pp.ink3),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: Space.s4,
                            vertical: Space.s3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.s1),
                Semantics(
                  button: true,
                  enabled: enabled,
                  label: sendLabel,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSend,
                    child: SizedBox(
                      width: Sizes.tap,
                      height: Sizes.tap,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: enabled ? pp.accent : pp.line,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Center(
                              child: AppIcon(
                                AppIconName.send,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
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
