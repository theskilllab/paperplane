import 'package:flutter/material.dart';

/// Shows a modal bottom sheet with a solid surface.
///
/// Returns the value the sheet is popped with, or null if dismissed.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: builder,
  );
}

/// Standard padded content for an app sheet.
class AppSheet extends StatelessWidget {
  /// Creates sheet content with an optional [title].
  const new({required this.child, this.title, super.key});

  /// Optional heading.
  final String? title;

  /// Sheet body.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title case final title?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          child,
        ],
      ),
    );
  }
}
