import 'package:flutter/material.dart';

import 'family.dart';

ColorScheme _light({
  required Color primary,
  required Color surface,
  required Color onSurface,
  required Color surfaceContainer,
}) {
  // Cards sit one tonal step above the background; keep the whole M3
  // container ramp on-brand instead of Flutter's near-background defaults
  // (unset roles made cards invisible — see dashboard blending fix).
  final low = Color.lerp(surface, surfaceContainer, 0.5)!;
  return ColorScheme.light(
    primary: primary,
    onPrimary: surface,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerLowest: surface,
    surfaceContainerLow: low,
    surfaceContainer: low,
    surfaceContainerHigh: surfaceContainer,
    surfaceContainerHighest: surfaceContainer,
    secondary: primary,
    onSecondary: surface,
  );
}

ColorScheme _dark({
  required Color primary,
  required Color surface,
  required Color onSurface,
  required Color surfaceContainer,
}) {
  final low = Color.lerp(surface, surfaceContainer, 0.5)!;
  return ColorScheme.dark(
    primary: primary,
    onPrimary: surface,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerLowest: surface,
    surfaceContainerLow: low,
    surfaceContainer: low,
    surfaceContainerHigh: surfaceContainer,
    surfaceContainerHighest: surfaceContainer,
    secondary: primary,
    onSecondary: surface,
  );
}

/// Light scheme per family (see dev plan §4 for hex table).
ColorScheme larmLightScheme(LarmThemeFamily family) {
  switch (family) {
    case LarmThemeFamily.mono:
      return _light(
        primary: const Color(0xFF0A0A0A),
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFFF0F0F0),
      );
    case LarmThemeFamily.midnight:
      return _light(
        primary: const Color(0xFF1B2B57),
        surface: const Color(0xFFF2F5FF),
        onSurface: const Color(0xFF060913),
        surfaceContainer: const Color(0xFFE2E9FB),
      );
    case LarmThemeFamily.arctic:
      return _light(
        primary: const Color(0xFF33505F),
        surface: const Color(0xFFFAFCFE),
        onSurface: const Color(0xFF1B2733),
        surfaceContainer: const Color(0xFFE6EDF3),
      );
    case LarmThemeFamily.forest:
      return _light(
        primary: const Color(0xFF1E4D33),
        surface: const Color(0xFFF6FAF6),
        onSurface: const Color(0xFF0B1510),
        surfaceContainer: const Color(0xFFE0EDE3),
      );
    case LarmThemeFamily.ember:
      return _light(
        primary: const Color(0xFF8A4B00),
        surface: const Color(0xFFFFFBF5),
        onSurface: const Color(0xFF221206),
        surfaceContainer: const Color(0xFFF7E8D2),
      );
    case LarmThemeFamily.ocean:
      return _light(
        primary: const Color(0xFF0B4F7C),
        surface: const Color(0xFFF4FAFF),
        onSurface: const Color(0xFF071522),
        surfaceContainer: const Color(0xFFDCEEFb),
      );
  }
}

/// Dark scheme per family.
ColorScheme larmDarkScheme(LarmThemeFamily family) {
  switch (family) {
    case LarmThemeFamily.mono:
      return _dark(
        primary: const Color(0xFFF5F5F5),
        surface: const Color(0xFF000000),
        onSurface: const Color(0xFFF5F5F5),
        surfaceContainer: const Color(0xFF161616),
      );
    case LarmThemeFamily.midnight:
      return _dark(
        primary: const Color(0xFF8AB4FF),
        surface: const Color(0xFF000000),
        onSurface: const Color(0xFFDCE6FF),
        surfaceContainer: const Color(0xFF0D1526),
      );
    case LarmThemeFamily.arctic:
      return _dark(
        primary: const Color(0xFF9FB8CC),
        surface: const Color(0xFF0E151D),
        onSurface: const Color(0xFFE6EEF5),
        surfaceContainer: const Color(0xFF1B2836),
      );
    case LarmThemeFamily.forest:
      return _dark(
        primary: const Color(0xFF7ED49A),
        surface: const Color(0xFF060D0A),
        onSurface: const Color(0xFFD2E8D5),
        surfaceContainer: const Color(0xFF0F1F16),
      );
    case LarmThemeFamily.ember:
      return _dark(
        primary: const Color(0xFFFFB454),
        surface: const Color(0xFF140C04),
        onSurface: const Color(0xFFFFE6C4),
        surfaceContainer: const Color(0xFF2A1A08),
      );
    case LarmThemeFamily.ocean:
      return _dark(
        primary: const Color(0xFF4FD1FF),
        surface: const Color(0xFF040D16),
        onSurface: const Color(0xFFCDEBFF),
        surfaceContainer: const Color(0xFF0B1C2B),
      );
  }
}

/// App [ThemeData] for a family + brightness. Painters must read colors from
/// `Theme.of(context).colorScheme`, never hardcode B&W.
ThemeData buildLarmTheme({
  required LarmThemeFamily family,
  required Brightness brightness,
}) {
  final scheme = brightness == Brightness.dark
      ? larmDarkScheme(family)
      : larmLightScheme(family);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      // Explicit: M3 Card otherwise falls back to surfaceContainerLow.
      color: scheme.surfaceContainerHighest,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  );
}

/// Clock-hand color for the hybrid hero (follows active scheme).
Color larmHandColor(ColorScheme scheme) => scheme.primary;

/// Countdown/progress ring color for the hybrid hero.
Color larmRingColor(ColorScheme scheme) => scheme.primary;
