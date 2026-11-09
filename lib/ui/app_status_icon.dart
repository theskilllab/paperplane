import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Issue status, drawn by color **and** shape, with a spoken label.
enum AppStatus {
  /// To do: empty circle.
  todo('To do', ['<circle cx="12" cy="12" r="8"/>']),

  /// In progress: circle with a dot.
  inProgress('In progress', [
    '<circle cx="12" cy="12" r="8"/>',
    '<circle cx="12" cy="12" r="2.4" fill="currentColor" stroke="none"/>',
  ]),

  /// Running: open arc that turns.
  running('Running', ['<path d="M12 4a8 8 0 0 1 8 8"/>']),

  /// In review: circle with the right half filled.
  review('In review', [
    '<circle cx="12" cy="12" r="8"/>',
    '<path d="M12 4a8 8 0 0 1 0 16z" fill="currentColor"/>',
  ]),

  /// Blocked: circle with a bar.
  blocked('Blocked', [
    '<circle cx="12" cy="12" r="8"/>',
    '<path d="M8.5 12h7"/>',
  ]),

  /// Done: circle with a check.
  done('Done', [
    '<circle cx="12" cy="12" r="8"/>',
    '<path d="M8.5 12.2l2.5 2.5 4.5-5"/>',
  ]),

  /// Backlog: dashed circle.
  backlog('Backlog', [
    '<circle cx="12" cy="12" r="8" stroke-dasharray="2.6 2.6"/>',
  ]),

  /// Cancelled: circle with a cross.
  cancelled('Cancelled', [
    '<circle cx="12" cy="12" r="8"/>',
    '<path d="M9.5 9.5l5 5M14.5 9.5l-5 5"/>',
  ]);

  new(this.label, this._parts);

  /// Spoken and visible name.
  final String label;

  final List<String> _parts;

  /// Color of the status.
  Color color(PaperplaneTokens pp) => switch (this) {
    todo => pp.todo,
    inProgress || running || review => pp.accent,
    blocked => pp.danger,
    done => pp.ok,
    backlog || cancelled => pp.idle,
  };

  String get _svg =>
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none" stroke="currentColor" stroke-width="1.9" '
      'stroke-linecap="round" stroke-linejoin="round">${_parts.join()}</svg>';
}

/// Status icon for list rows (size 20) and detail headers (size 18).
class AppStatusIcon extends StatefulWidget {
  /// Creates the icon.
  const new(this.status, {this.size = 20, super.key});

  /// Which status.
  final AppStatus status;

  /// Width and height.
  final double size;

  @override
  State<AppStatusIcon> createState() => _AppStatusIconState();
}

class _AppStatusIconState extends State<AppStatusIcon>
    with SingleTickerProviderStateMixin {
  AnimationController? _spin;

  @override
  void dispose() {
    _spin?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    Widget icon = SvgPicture.string(
      widget.status._svg,
      width: widget.size,
      height: widget.size,
      theme: SvgTheme(currentColor: widget.status.color(pp)),
      excludeFromSemantics: true,
    );

    final spins =
        widget.status == AppStatus.running && !Motion.reduced(context);
    if (spins) {
      final controller = _spin ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      );
      if (!controller.isAnimating) controller.repeat();
      icon = RotationTransition(turns: controller, child: icon);
    } else {
      _spin?.stop();
    }
    return Semantics(label: widget.status.label, image: true, child: icon);
  }
}
