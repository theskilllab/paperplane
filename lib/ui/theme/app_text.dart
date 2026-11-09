import 'package:flutter/painting.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// Type scale from the design spec §1.2. Font is Inter (variable TTF).
///
/// Weights such as 650 and 720 need the variable axis, so every style sets
/// both `fontWeight` (nearest static weight, for fallback) and
/// `fontVariations`. Letter spacing is in logical pixels (em × size).
class PaperplaneText {
  /// Creates the scale for the colors of the given tokens.
  const new(this._tokens);

  final PaperplaneTokens _tokens;

  /// Font family name registered in `pubspec.yaml`.
  static const family = 'Inter';

  static const _features = [FontFeature('cv11'), FontFeature('ss03')];

  TextStyle _style({
    required double size,
    required double weight,
    required Color color,
    double height = 1.5,
    double spacing = 0,
    String? fontFamily,
  }) => TextStyle(
    fontFamily: fontFamily ?? family,
    fontSize: size,
    height: height,
    letterSpacing: spacing,
    color: color,
    fontWeight: FontWeight.values[((weight / 100).round().clamp(1, 9)) - 1],
    fontVariations: [FontVariation('wght', weight)],
    fontFeatures: _features,
  );

  /// Root screen title, 30/1.15, 720.
  TextStyle get largeTitle => _style(
    size: 30,
    weight: 720,
    color: _tokens.ink,
    height: 1.15,
    spacing: -0.75,
  );

  /// Sheet and issue title, 20/1.3, 650.
  TextStyle get h => _style(
    size: 20,
    weight: 650,
    color: _tokens.ink,
    height: 1.3,
    spacing: -0.2,
  );

  /// Approval title, 17/1.3, 600.
  TextStyle get h3 => _style(
    size: 17,
    weight: 600,
    color: _tokens.ink,
    height: 1.3,
    spacing: -0.17,
  );

  /// Body text, 16/1.5, 400.
  TextStyle get body => _style(size: 16, weight: 400, color: _tokens.ink);

  /// Row title in lists, 16, 550.
  TextStyle get bodyStrong => _style(size: 16, weight: 550, color: _tokens.ink);

  /// Inbox row title, 16/1.35, 500; two lines at most.
  TextStyle get rowTitle =>
      _style(size: 16, weight: 500, color: _tokens.ink, height: 1.35);

  /// Helper and meta text, 14, 400.
  TextStyle get small => _style(size: 14, weight: 400, color: _tokens.ink2);

  /// Field labels and small buttons, 14, 600.
  TextStyle get smallStrong =>
      _style(size: 14, weight: 600, color: _tokens.ink);

  /// Timestamps and pills, 12, 400.
  TextStyle get micro => _style(size: 12, weight: 400, color: _tokens.ink3);

  /// Pill text, 12, 600.
  TextStyle get microStrong =>
      _style(size: 12, weight: 600, color: _tokens.ink);

  /// Top bar title, 13, 650, tracked. Apply upper-case to the string.
  TextStyle get barTitle =>
      _style(size: 13, weight: 650, color: _tokens.ink, spacing: 1.17);

  /// Section title, 12, 650, tracked. Apply upper-case to the string.
  TextStyle get sectionTitle =>
      _style(size: 12, weight: 650, color: _tokens.ink3, spacing: 1.08);

  /// Group header, 13, 650, tracked. Apply upper-case to the string.
  TextStyle get groupHeader =>
      _style(size: 13, weight: 650, color: _tokens.ink, spacing: 0.91);

  /// Count next to a group header, 13, 500, no tracking.
  TextStyle get groupCount =>
      _style(size: 13, weight: 500, color: _tokens.ink3);

  /// Issue ids such as `ABC-12`, 13, monospace.
  TextStyle get mono => const TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['SF Mono', 'monospace'],
    fontSize: 13,
    height: 1.5,
    letterSpacing: -0.13,
  ).copyWith(color: _tokens.ink3);

  /// Button label, 16, 600.
  TextStyle get button => _style(size: 16, weight: 600, color: _tokens.ink);

  /// Empty state title, 18, 600.
  TextStyle get emptyTitle => _style(size: 18, weight: 600, color: _tokens.ink);
}
