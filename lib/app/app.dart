import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/app/router.dart';
import 'package:paperplane/ui/ui.dart';

/// Root widget of Paperplane.
class PaperplaneApp extends ConsumerWidget {
  /// Creates the root widget.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Paperplane',
      // The ribbon covers the "+" button in debug builds and in screenshots.
      debugShowCheckedModeBanner: false,
      theme: buildPaperplaneTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
