import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/app/router.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/ui/ui.dart';

/// Root widget of Paperplane.
///
/// While the app is in the foreground it checks the board key once an hour,
/// so a key that turns seven days old is replaced without a restart
/// (PRD S1 AC9). The timer stops when the app goes to the background.
class PaperplaneApp extends ConsumerStatefulWidget {
  /// Creates the root widget.
  const new({super.key});

  @override
  ConsumerState<PaperplaneApp> createState() => _PaperplaneAppState();
}

class _PaperplaneAppState extends ConsumerState<PaperplaneApp>
    with WidgetsBindingObserver {
  static const _checkInterval = Duration(hours: 1);
  Timer? _rotationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _rotationTimer?.cancel();
      _rotationTimer = null;
      return;
    }
    _checkRotation();
    _rotationTimer ??= Timer.periodic(_checkInterval, (_) => _checkRotation());
  }

  void _checkRotation() {
    unawaited(ref.read(sessionControllerProvider.notifier).rotateIfNeeded());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Paperplane',
      // The ribbon covers the "+" button in debug builds and in screenshots.
      debugShowCheckedModeBanner: false,
      theme: buildPaperplaneTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
