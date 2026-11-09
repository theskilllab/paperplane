import 'package:flutter/material.dart';
import 'package:paperplane/ui/theme/app_text.dart';

/// Design tokens from the design spec §1, as one theme extension.
///
/// Read them with `context.pp`. Widgets never use raw hex values.
@immutable
class PaperplaneTokens extends ThemeExtension<PaperplaneTokens> {
  /// Creates tokens. Use [PaperplaneTokens.light] for the app.
  const new({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.accentSoft,
    required this.ok,
    required this.todo,
    required this.danger,
    required this.warnSoft,
    required this.dangerSoft,
    required this.dangerInk,
    required this.warnInk,
    required this.inkHover,
    required this.switchOff,
    required this.scrim,
    required this.idle,
    required this.barScrolled,
  });

  /// The light palette. Dark is out of scope for M2 (design spec D5).
  const new light()
    : bg = const Color(0xFFFFFFFF),
      panel = const Color(0xFFF4F4F5),
      panel2 = const Color(0xFFEBEBED),
      line = const Color(0xFFE4E4E7),
      ink = const Color(0xFF111214),
      ink2 = const Color(0xFF53565E),
      ink3 = const Color(0xFF686B73),
      accent = const Color(0xFF4A56D6),
      accentSoft = const Color(0xFFE8EAFC),
      ok = const Color(0xFF2C8A4B),
      todo = const Color(0xFFB86E0A),
      danger = const Color(0xFFC3352B),
      warnSoft = const Color(0xFFFBECCD),
      dangerSoft = const Color(0xFFFBE2DF),
      dangerInk = const Color(0xFFB8312A),
      warnInk = const Color(0xFF7A4A05),
      inkHover = const Color(0xFF2A2C31),
      switchOff = const Color(0xFFC9CBD1),
      scrim = const Color(0x73111214),
      idle = const Color(0xFF8B8E96),
      barScrolled = const Color(0xE6FFFFFF);

  /// Screen, card and sheet background.
  final Color bg;

  /// Pressed row, disabled button, skeleton, pill.
  final Color panel;

  /// Selected state on Android.
  final Color panel2;

  /// Hairlines and dividers.
  final Color line;

  /// Text, primary button.
  final Color ink;

  /// Secondary text (7:1 on [bg]).
  final Color ink2;

  /// Timestamps and helper text (5.2:1 on [bg]).
  final Color ink3;

  /// Links, focus ring, in-progress.
  final Color accent;

  /// Info banner and blue pill background.
  final Color accentSoft;

  /// Done.
  final Color ok;

  /// To do.
  final Color todo;

  /// Blocked, danger button, error text.
  final Color danger;

  /// Warning pill and banner background.
  final Color warnSoft;

  /// Error pill and banner background.
  final Color dangerSoft;

  /// Text and icons on [dangerSoft]. Not in the design spec: `danger` on
  /// `dangerSoft` is 4.41:1, below the 4.5:1 the spec itself requires, so this
  /// slightly darker red (4.86:1) is used there. Needs the designer's OK.
  final Color dangerInk;

  /// Text on [warnSoft].
  final Color warnInk;

  /// Primary button on pointer hover.
  final Color inkHover;

  /// Switch track, off.
  final Color switchOff;

  /// Behind sheets.
  final Color scrim;

  /// Backlog and other.
  final Color idle;

  /// Bar background after scroll.
  final Color barScrolled;

  /// Type scale built on these colors.
  PaperplaneText get text => PaperplaneText(this);

  @override
  PaperplaneTokens copyWith({Color? ink, Color? accent}) => PaperplaneTokens(
    bg: bg,
    panel: panel,
    panel2: panel2,
    line: line,
    ink: ink ?? this.ink,
    ink2: ink2,
    ink3: ink3,
    accent: accent ?? this.accent,
    accentSoft: accentSoft,
    ok: ok,
    todo: todo,
    danger: danger,
    warnSoft: warnSoft,
    dangerSoft: dangerSoft,
    dangerInk: dangerInk,
    warnInk: warnInk,
    inkHover: inkHover,
    switchOff: switchOff,
    scrim: scrim,
    idle: idle,
    barScrolled: barScrolled,
  );

  @override
  PaperplaneTokens lerp(ThemeExtension<PaperplaneTokens>? other, double t) {
    if (other is! PaperplaneTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return PaperplaneTokens(
      bg: mix(bg, other.bg),
      panel: mix(panel, other.panel),
      panel2: mix(panel2, other.panel2),
      line: mix(line, other.line),
      ink: mix(ink, other.ink),
      ink2: mix(ink2, other.ink2),
      ink3: mix(ink3, other.ink3),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      ok: mix(ok, other.ok),
      todo: mix(todo, other.todo),
      danger: mix(danger, other.danger),
      warnSoft: mix(warnSoft, other.warnSoft),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      dangerInk: mix(dangerInk, other.dangerInk),
      warnInk: mix(warnInk, other.warnInk),
      inkHover: mix(inkHover, other.inkHover),
      switchOff: mix(switchOff, other.switchOff),
      scrim: mix(scrim, other.scrim),
      idle: mix(idle, other.idle),
      barScrolled: mix(barScrolled, other.barScrolled),
    );
  }
}

/// `context.pp` gives the tokens of the nearest theme.
extension PaperplaneContext on BuildContext {
  /// Design tokens. Falls back to the light palette outside a Paperplane
  /// theme, so widgets still render in bare tests.
  PaperplaneTokens get pp =>
      Theme.of(this).extension<PaperplaneTokens>() ?? const .light();
}

/// Spacing scale (design spec §1.3).
abstract final class Space {
  /// 4.
  static const double s1 = 4;

  /// 8.
  static const double s2 = 8;

  /// 12.
  static const double s3 = 12;

  /// 16.
  static const double s4 = 16;

  /// 24.
  static const double s5 = 24;

  /// 32.
  static const double s6 = 32;

  /// Horizontal screen padding.
  static const double pageH = 16;

  /// Bottom screen padding.
  static const double pageBottom = 24;
}

/// Sizes (design spec §1.3).
abstract final class Sizes {
  /// Minimum tap target on iOS.
  static const double tap = 44;

  /// Minimum height of buttons and inputs.
  static const double tapLg = 48;

  /// Minimum row height.
  static const double rowH = 56;

  /// Minimum height of an approval row.
  static const double approvalRowH = 64;

  /// Minimum top bar height.
  static const double barH = 52;

  /// Widest content column on tablets (design spec §5).
  static const double column = 640;

  /// Width of a form sheet on tablets.
  static const double formSheet = 540;

  /// Largest text scale for bars and buttons.
  static const double maxBarTextScale = 1.6;
}

/// Corner radii (design spec §1.3).
abstract final class Radii {
  /// Default, 10.
  static const double md = 10;

  /// Small, 8.
  static const double sm = 8;

  /// Pill.
  static const double pill = 999;

  /// Top corners of a sheet.
  static const double sheet = 22;

  /// Composer input.
  static const double composer = 22;
}

/// Shadows (design spec §1.4). Cards use a border, not a shadow.
abstract final class Shadows {
  /// Bottom sheet.
  static const List<BoxShadow> sheet = [
    BoxShadow(color: Color(0x24111214), offset: Offset(0, -8), blurRadius: 32),
  ];

  /// Pull-to-refresh indicator.
  static const List<BoxShadow> pullIndicator = [
    BoxShadow(color: Color(0x33111214), offset: Offset(0, 2), blurRadius: 8),
  ];
}

/// Durations and curves (design spec §1.5).
abstract final class Motion {
  /// Button press, hover.
  static const Duration fast = Duration(milliseconds: 160);

  /// Sheet settle, scrim fade, toast in.
  static const Duration med = Duration(milliseconds: 260);

  /// Sheet in.
  static const Duration nav = Duration(milliseconds: 320);

  /// Spinner turn.
  static const Duration spin = Duration(milliseconds: 800);

  /// Skeleton shimmer.
  static const Duration shimmer = Duration(milliseconds: 1200);

  /// Curve for `med` and `nav`.
  static const Curve emphasized = Cubic(0.32, 0.72, 0, 1);

  /// Returns [d], or 1 ms when the user turned on Reduce Motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context)
      ? const Duration(milliseconds: 1)
      : d;

  /// True when animation should be skipped.
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

/// Caps the text scale for bars and buttons, whose heights are fixed
/// (design spec §1.2). Rows are not wrapped in this; they grow instead.
class ClampedTextScale extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, this.max = Sizes.maxBarTextScale, super.key});

  /// Largest scale factor allowed.
  final double max;

  /// Content to cap.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: max),
      ),
      child: child,
    );
  }
}
