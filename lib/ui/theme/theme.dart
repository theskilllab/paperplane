import 'package:flutter/material.dart';
import 'package:paperplane/ui/theme/app_text.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Builds the app theme from [PaperplaneTokens].
///
/// Material widgets that survive inside our own components read this theme;
/// components read `context.pp` directly.
ThemeData buildPaperplaneTheme({PaperplaneTokens tokens = const .light()}) {
  final text = tokens.text;
  final scheme = ColorScheme.light(
    primary: tokens.ink,
    secondary: tokens.accent,
    onSecondary: Colors.white,
    error: tokens.danger,
    surface: tokens.bg,
    onSurface: tokens.ink,
    outline: tokens.line,
    outlineVariant: tokens.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: PaperplaneText.family,
    scaffoldBackgroundColor: tokens.bg,
    canvasColor: tokens.bg,
    dividerColor: tokens.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: TextTheme(
      displaySmall: text.largeTitle,
      headlineSmall: text.h,
      titleLarge: text.h,
      titleMedium: text.h3,
      bodyLarge: text.body,
      bodyMedium: text.body,
      bodySmall: text.small,
      labelLarge: text.button,
      labelMedium: text.smallStrong,
      labelSmall: text.micro,
    ),
    extensions: [tokens],
  );
}
