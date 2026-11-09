import 'package:flutter/material.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Placeholder row shown while the first load runs (PRD G1). Pulses between
/// `panel` and a lighter gray; static under Reduce Motion.
class AppSkeletonRow extends StatefulWidget {
  /// Creates a placeholder.
  const new({super.key});

  @override
  State<AppSkeletonRow> createState() => _AppSkeletonRowState();
}

class _AppSkeletonRowState extends State<AppSkeletonRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.shimmer ~/ 2,
  );

  static const _light = Color(0xFFFAFAFA);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    if (Motion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(pp.panel, _light, _controller.value),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: const SizedBox(height: 64, width: double.infinity),
      ),
    );
  }
}
