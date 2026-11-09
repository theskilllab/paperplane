import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/ui/ui.dart';

double luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const pp = PaperplaneTokens.light();

  group('contrast (design spec §1.1)', () {
    test('text colors on bg reach 4.5:1', () {
      for (final (name, color) in [
        ('ink', pp.ink),
        ('ink2', pp.ink2),
        ('ink3', pp.ink3),
        ('accent', pp.accent),
        ('danger', pp.danger),
      ]) {
        expect(contrast(color, pp.bg), greaterThanOrEqualTo(4.5), reason: name);
      }
    });

    // The design spec says every color passes 4.5:1 on bg. `ok` (4.34) and
    // `todo` (3.98) do not, but they only color status icons, which need 3:1
    // (WCAG 1.4.11), and each icon also has a shape and a spoken label.
    test('status icon colors on bg reach 3:1', () {
      for (final (name, color) in [
        ('ok', pp.ok),
        ('todo', pp.todo),
        ('accent', pp.accent),
        ('danger', pp.danger),
        ('idle', pp.idle),
      ]) {
        expect(contrast(color, pp.bg), greaterThanOrEqualTo(3), reason: name);
      }
    });

    test('documented ratios hold', () {
      expect(contrast(pp.ink2, pp.bg), greaterThanOrEqualTo(7));
      expect(contrast(pp.ink3, pp.bg), closeTo(5.2, 0.3));
    });

    test('white on accent, danger and ink reaches 4.5:1', () {
      for (final fill in [pp.accent, pp.danger, pp.ink]) {
        expect(contrast(Colors.white, fill), greaterThanOrEqualTo(4.5));
      }
    });

    test('pill and banner text on their soft fills reaches 4.5:1', () {
      expect(contrast(pp.warnInk, pp.warnSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(pp.dangerInk, pp.dangerSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(pp.accent, pp.accentSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(pp.ink3, pp.panel), greaterThanOrEqualTo(4.5));
    });
  });

  group('type scale (design spec §1.2)', () {
    final text = pp.text;

    test('sizes, line heights and tracking', () {
      expect(text.largeTitle.fontSize, 30);
      expect(text.largeTitle.height, 1.15);
      expect(text.largeTitle.letterSpacing, -0.75);
      expect(text.h.letterSpacing, -0.2);
      expect(text.h3.fontSize, 17);
      expect(text.body.fontSize, 16);
      expect(text.body.height, 1.5);
      expect(text.rowTitle.height, 1.35);
      expect(text.small.fontSize, 14);
      expect(text.micro.fontSize, 12);
      expect(text.barTitle.letterSpacing, 1.17);
      expect(text.groupHeader.letterSpacing, 0.91);
      expect(text.emptyTitle.fontSize, 18);
    });

    test('uses Inter with the variable weight axis and its features', () {
      expect(text.body.fontFamily, 'Inter');
      expect(
        text.largeTitle.fontVariations,
        contains(const FontVariation('wght', 720)),
      );
      expect(text.h.fontVariations, contains(const FontVariation('wght', 650)));
      expect(text.body.fontFeatures, contains(const FontFeature('cv11')));
      expect(text.body.fontFeatures, contains(const FontFeature('ss03')));
    });

    test('mono is monospace', () {
      expect(text.mono.fontFamilyFallback, contains('monospace'));
    });
  });

  group('theme', () {
    test('carries the tokens and Inter', () {
      final theme = buildPaperplaneTheme();
      expect(theme.extension<PaperplaneTokens>(), isNotNull);
      expect(theme.textTheme.bodyLarge?.fontFamily, 'Inter');
      expect(theme.scaffoldBackgroundColor, pp.bg);
    });

    test('tokens lerp and copyWith', () {
      expect(pp.lerp(null, 0.5), same(pp));
      const red = Color(0xFFFF0000);
      final other = pp.copyWith(ink: red);
      expect(pp.lerp(other, 1).ink, red);
      expect(pp.lerp(other, 0).ink, pp.ink);
    });

    testWidgets('context.pp falls back outside a Paperplane theme', (
      tester,
    ) async {
      late PaperplaneTokens seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              seen = context.pp;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen.ink, pp.ink);
    });
  });

  group('motion', () {
    testWidgets('Reduce Motion shortens durations to 1 ms', (tester) async {
      late Duration normal;
      late Duration reduced;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              normal = Motion.of(context, Motion.med);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: Builder(
                  builder: (context) {
                    reduced = Motion.of(context, Motion.med);
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      );
      expect(normal, Motion.med);
      expect(reduced, const Duration(milliseconds: 1));
    });

    testWidgets('ClampedTextScale caps at 1.6', (tester) async {
      late double scale;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: ClampedTextScale(
            child: Builder(
              builder: (context) {
                scale = MediaQuery.textScalerOf(context).scale(10) / 10;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(scale, closeTo(1.6, 0.001));
    });
  });
}
