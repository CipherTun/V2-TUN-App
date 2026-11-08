import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/models.dart';

const googleBlue = Color(0xFF4285F4);
const googleRed = Color(0xFFEA4335);
const googleYellow = Color(0xFFFBBC05);
const googleGreen = Color(0xFF34A853);
const googleColors = [googleBlue, googleRed, googleYellow, googleGreen];

class Accent {
  const Accent(this.name, this.color);
  final String name;
  final Color color;
}

/// Seven presets. Index 0 is the default and animates through the four Google colors.
const accents = [
  Accent('Google', Color(0xFF8AB4F8)),
  Accent('Steel', Color(0xFF7C9CBF)),
  Accent('Coral', Color(0xFFFF8A75)),
  Accent('Amber', Color(0xFFF6BF4B)),
  Accent('Emerald', Color(0xFF4FD1A1)),
  Accent('Violet', Color(0xFFA78BFA)),
  Accent('Rose', Color(0xFFF472B6)),
];
const customIndex = 7;

extension SettingsAccent on Settings {
  bool get isGoogle => accentIndex == 0;
  Color get accent => accentIndex == customIndex ? Color(customAccent) : accents[accentIndex.clamp(0, 6)].color;
}

// Greyish blue and black surfaces.
const bg = Color(0xFF080B10);
const surface = Color(0xFF10151D);
const surfaceHigh = Color(0xFF182030);
const outline = Color(0xFF28344A);
const textPrimary = Color(0xFFE6EBF3);
const textMuted = Color(0xFF8795AB);

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
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark).copyWith(
    primary: accent,
    onPrimary: const Color(0xFF05080D),
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
    scaffoldBackgroundColor: bg,
    textTheme: text,
    fontFamily: 'DMSans',
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: surface, elevation: 0, margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: outline)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface.withValues(alpha: 0.96),
      indicatorColor: accent.withValues(alpha: 0.18),
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith((s) =>
          sans(12, w: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? accent : textMuted)),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? accent : textMuted)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF05080D) : textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : surfaceHigh),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : outline),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: surfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent)),
      labelStyle: text.bodySmall,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating, backgroundColor: surfaceHigh, contentTextStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

/// A rotating ring painted with the four Google colors, or with shades of one accent.
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

List<Color> ringColors(Settings s) => s.isGoogle
    ? googleColors
    : [s.accent, s.accent.withValues(alpha: 0.25), s.accent, s.accent.withValues(alpha: 0.25)];

double wobble(double t, double phase) => math.sin(t * 2 * math.pi + phase);
