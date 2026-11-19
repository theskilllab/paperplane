import 'package:flutter/material.dart';
import 'package:paperplane/ui/app_sheet.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// A tappable "Label  Value ›" chip that opens a picker sheet.
///
/// Used for the assignee and project fields of S7 and for the @agent button of
/// the S6 composer. The whole chip is one 44 pt button; a screen reader hears
/// "Label: value".
class PickerChip extends StatelessWidget {
  /// Creates the chip. A null [onTap] disables it (40% opacity).
  const new({
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    super.key,
  });

  /// Field name, for example "Assignee".
  final String label;

  /// Current choice, for example "Chief Example" or "None".
  final String value;

  /// Opens the picker. Null disables the chip.
  final VoidCallback? onTap;

  /// Optional icon before the label.
  final AppIconName? icon;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label: $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.tap),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: pp.line),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s3,
                  vertical: Space.s2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      AppIcon(icon!, size: 16, color: pp.ink2),
                      const SizedBox(width: Space.s1),
                    ],
                    Text(label, style: pp.text.small),
                    const SizedBox(width: Space.s2),
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: pp.text.smallStrong.copyWith(color: pp.ink),
                      ),
                    ),
                    const SizedBox(width: Space.s1),
                    AppIcon(AppIconName.chev, size: 14, color: pp.ink3),
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

/// One row of a picker sheet.
@immutable
class PickerOption<T> {
  /// Creates an option.
  const new({required this.value, required this.label, this.subtitle});

  /// What the sheet returns for this row.
  final T value;

  /// Row text.
  final String label;

  /// Optional second line, for example an agent's role.
  final String? subtitle;
}

/// What a picker sheet returns. A null [value] means the user chose the "none"
/// row; a dismissed sheet returns no choice at all.
@immutable
class PickerChoice<T> {
  /// Creates a choice.
  const new(this.value);

  /// The picked value, or null for "none".
  final T? value;
}

/// Opens a list sheet and returns the user's [PickerChoice], or null when the
/// sheet is dismissed.
///
/// [selected] gets a check mark. A non-null [noneLabel] adds a first row that
/// returns `PickerChoice(null)`. With no options, [emptyText] is shown.
Future<PickerChoice<T>?> showPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
  String? noneLabel,
  String emptyText = 'Nothing to choose from.',
}) => showAppSheet<PickerChoice<T>>(
  context: context,
  builder: (sheetContext) => AppSheet(
    title: title,
    child: _PickerList<T>(
      options: options,
      selected: selected,
      noneLabel: noneLabel,
      emptyText: emptyText,
      onPick: (value) => Navigator.of(sheetContext).pop(PickerChoice<T>(value)),
    ),
  ),
);

class _PickerList<T> extends StatelessWidget {
  const new({
    required this.options,
    required this.selected,
    required this.noneLabel,
    required this.emptyText,
    required this.onPick,
  });

  final List<PickerOption<T>> options;
  final T? selected;
  final String? noneLabel;
  final String emptyText;
  final void Function(T? value) onPick;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    if (options.isEmpty && noneLabel == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s4),
        child: Text(emptyText, style: pp.text.small),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (noneLabel case final none?)
          _Row(
            label: none,
            selected: selected == null,
            onTap: () => onPick(null),
          ),
        for (final option in options)
          _Row(
            label: option.label,
            subtitle: option.subtitle,
            selected: option.value == selected,
            onTap: () => onPick(option.value),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return Semantics(
      button: true,
      selected: selected,
      label: subtitle == null ? label : '$label, $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.rowH),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: pp.text.body),
                    if (subtitle case final sub?)
                      Text(sub, style: pp.text.micro),
                  ],
                ),
              ),
              if (selected) AppIcon(AppIconName.check, color: pp.accent),
            ],
          ),
        ),
      ),
    );
  }
}
