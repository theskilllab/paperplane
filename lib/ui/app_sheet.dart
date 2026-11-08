import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:paperplane/ui/app_error_text.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Screens at least this wide get a centered form sheet instead of a bottom
/// sheet (design spec §5).
const double kFormSheetBreakpoint = 600;

/// Shows a modal sheet with a solid surface and returns what it is popped
/// with, or null if dismissed.
///
/// Phones get a bottom sheet (22 top radius, grabber, at most 90% high).
/// Tablets get a centered 540 pt form sheet without a grabber.
///
/// While [locked] is true, Back and a tap on the scrim do nothing, so a
/// request in flight cannot be dismissed by accident. A drag on the grabber
/// can still close a phone sheet; the caller's `SubmitController` keeps the
/// request safe either way.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  ValueListenable<bool>? locked,
}) {
  Widget guarded(BuildContext context) =>
      _SheetGuard(locked: locked, child: builder(context));

  final width = MediaQuery.sizeOf(context).width;
  if (width >= kFormSheetBreakpoint) {
    return showDialog<T>(
      context: context,
      barrierColor: context.pp.scrim,
      builder: (context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.formSheet),
          child: _SheetFrame(
            grabber: false,
            radius: BorderRadius.circular(Radii.sheet),
            child: guarded(context),
          ),
        ),
      ),
    );
  }

  final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: context.pp.scrim,
    constraints: BoxConstraints(maxHeight: maxHeight),
    builder: (context) => _SheetFrame(
      grabber: true,
      radius: const BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      child: guarded(context),
    ),
  );
}

class _SheetGuard extends StatelessWidget {
  const new({required this.child, this.locked});

  final ValueListenable<bool>? locked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final locked = this.locked;
    if (locked == null) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: locked,
      builder: (context, isLocked, child) =>
          PopScope(canPop: !isLocked, child: child!),
      child: child,
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const new({required this.child, required this.grabber, required this.radius});

  final Widget child;
  final bool grabber;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pp.bg,
        borderRadius: radius,
        boxShadow: Shadows.sheet,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: pp.bg,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (grabber)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.s2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: pp.line,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: const SizedBox(width: 40, height: 5),
                      ),
                    )
                  else
                    const SizedBox(height: Space.s4),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard padded content for an app sheet: optional [title], [child], and
/// an optional inline [errorText] (a failed submit keeps the sheet open).
class AppSheet extends StatelessWidget {
  /// Creates sheet content.
  const new({required this.child, this.title, this.errorText, super.key});

  /// Optional heading.
  final String? title;

  /// Sheet body.
  final Widget child;

  /// Inline error shown under [child].
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final title?)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s4),
              child: Semantics(
                header: true,
                child: Text(title, style: pp.text.h),
              ),
            ),
          child,
          if (errorText case final text?) ...[
            const SizedBox(height: Space.s3),
            AppErrorText(text),
          ],
        ],
      ),
    );
  }
}
