import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/models.dart';

// ---- palette -----------------------------------------------------------------
// Greyish blue over black, one soft accent. Taken from the Xray dashboard design.

/// Status colors. The google* names are kept so every page that used them keeps compiling.
const good = Color(0xFF5FC48D);
const warn = Color(0xFFE7B452);
const bad = Color(0xFFE5697A);
const googleBlue = Color(0xFF5B8DEF);
const googleRed = bad;
const googleYellow = warn;
const googleGreen = good;
const googleColors = [googleBlue, googleRed, googleYellow, googleGreen];

class Accent {
  const Accent(this.name, this.color);
  final String name;
  final Color color;
}

/// Seven presets. Index 0 is the default, a calm slightly desaturated turquoise.
const accents = [
  Accent('Lagoon', Color(0xFF5BB8AE)),
  Accent('Blue', Color(0xFF5B8DEF)),
  Accent('Steel', Color(0xFF7C9CBF)),
  Accent('Green', Color(0xFF63C58A)),
  Accent('Pink', Color(0xFFE7799F)),
  Accent('Teal', Color(0xFF1FA3A0)),
  Accent('Amber', Color(0xFFE7B452)),
];
const customIndex = 7;

extension SettingsAccent on Settings {
  /// Kept for older code; there is no multi-color accent any more.
  bool get isGoogle => false;
  Color get accent => accentIndex == customIndex ? Color(customAccent) : accents[accentIndex.clamp(0, 6)].color;
}

const bg = Color(0xFF090D13); // top of the page gradient
const bgBottom = Color(0xFF17212F); // bottom of the page gradient
const steel = Color(0xFF3F5878); // greyish blue
const surface = Color(0xFF131C28); // dialogs and sheets (solid)
const surfaceHigh = Color(0xFF1C2735);
const outline = Color(0xFF2A3544);
const textPrimary = Color(0xFFE9EFF6);
const textMuted = Color(0xFF8DA0B6);
const glass = Color(0x0EFFFFFF); // white at 5.5%: cards over the gradient
const glassStroke = Color(0x1AFFFFFF); // white at 10%

/// Text color that stays readable on top of [accent].
Color onAccent(Color accent) => accent.computeLuminance() > .45 ? const Color(0xFF0A1118) : Colors.white;

TextStyle sans(double size, {FontWeight w = FontWeight.w400, Color? color, double? height, double? spacing}) => TextStyle(
      fontFamily: 'DMSans', fontSize: size, color: color, height: height, letterSpacing: spacing,
      fontWeight: w, fontVariations: [FontVariation('wght', w.value.toDouble())],
    );

TextStyle serif(double size, {FontWeight w = FontWeight.w500, Color? color, double? height}) => TextStyle(
      fontFamily: 'Newsreader', fontSize: size, color: color, height: height,
      fontWeight: w, fontVariations: [FontVariation('wght', w.value.toDouble())],
    );

TextStyle mono(double size, {Color? color}) =>
    TextStyle(fontFamily: 'JetBrainsMono', fontSize: size, color: color, height: 1.4);

ThemeData buildTheme(Color accent, Brightness b) {
  final on = onAccent(accent);
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark).copyWith(
    primary: accent,
    onPrimary: on,
    surface: surface,
    onSurface: textPrimary,
    surfaceContainerLowest: bg,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: surfaceHigh,
    surfaceContainerHighest: surfaceHigh,
    outline: outline,
    outlineVariant: outline,
  );
  final text = TextTheme(
    displaySmall: serif(34, w: FontWeight.w500, color: textPrimary),
    headlineMedium: serif(28, color: textPrimary),
    headlineSmall: serif(24, color: textPrimary),
    titleLarge: serif(22, color: textPrimary),
    titleMedium: sans(16, w: FontWeight.w600, color: textPrimary),
    titleSmall: sans(14, w: FontWeight.w600, color: textPrimary),
    bodyLarge: sans(16, color: textPrimary, height: 1.4),
    bodyMedium: sans(14, color: textPrimary, height: 1.4),
    bodySmall: sans(12, color: textMuted, height: 1.4),
    labelLarge: sans(14, w: FontWeight.w600, color: textPrimary),
    labelMedium: sans(12, w: FontWeight.w500, color: textMuted, spacing: 0.4),
    labelSmall: sans(11, w: FontWeight.w500, color: textMuted, spacing: 0.5),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Transparent: the page gradient is painted once, behind the whole navigator (see AppBackdrop).
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: text,
    fontFamily: 'DMSans',
    splashFactory: InkSparkle.splashFactory,
    dividerColor: glassStroke,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, titleTextStyle: text.titleLarge,
    ),
    // Cards are frosted glass: a faint white over the gradient with a hairline border.
    cardTheme: CardThemeData(
      color: glass, elevation: 0, margin: EdgeInsets.zero, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: glassStroke)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface.withValues(alpha: 0.88),
      surfaceTintColor: Colors.transparent,
      indicatorColor: accent.withValues(alpha: 0.18),
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith((s) =>
          sans(12, w: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? accent : textMuted)),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? accent : textMuted)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? on : textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : textMuted.withValues(alpha: 0.25)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent, thumbColor: accent, inactiveTrackColor: textMuted.withValues(alpha: 0.25),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: surfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent)),
      labelStyle: text.bodySmall,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating, backgroundColor: surfaceHigh, contentTextStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

/// A rotating ring painted with a few colors. No page uses it for the connect button any more.
class SweepRing extends StatelessWidget {
  const SweepRing({super.key, required this.angle, required this.size, required this.stroke, required this.colors, this.opacity = 1});
  final double angle; // radians
  final double size, stroke, opacity;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            transform: GradientRotation(angle),
            colors: [...colors, colors.first],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(stroke),
          child: const DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: bg)),
        ),
      ),
    );
  }
}

List<Color> ringColors(Settings s) =>
    [s.accent, s.accent.withValues(alpha: 0.25), s.accent, s.accent.withValues(alpha: 0.25)];

double wobble(double t, double phase) => math.sin(t * 2 * math.pi + phase);
