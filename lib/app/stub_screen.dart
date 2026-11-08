import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:paperplane/ui/ui.dart';

/// Placeholder for a screen a later PR builds. It keeps every route
/// resolvable so screens can link to each other from day one.
class StubScreen extends StatelessWidget {
  /// Creates a stub for [screen] (for example `S4 Approval`), built in
  /// [builtIn] (for example `PR 2`).
  const new({required this.screen, required this.builtIn, super.key});

  /// Screen name from the PRD.
  final String screen;

  /// PR that replaces this stub.
  final String builtIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppNavBar(
        title: screen,
        onBack: context.canPop() ? context.pop : null,
      ),
      body: AppEmptyState(
        icon: AppIconName.plane,
        title: screen,
        message: 'Built in $builtIn.',
      ),
    );
  }
}
