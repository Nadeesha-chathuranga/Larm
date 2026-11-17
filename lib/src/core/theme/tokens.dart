import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Aurora palette: deep indigo-black glass with violet, cyan and mint accents.
abstract final class LarmPalette {
  static const Color background = Color(0xFF070A16);
  static const Color surface = Color(0xFF111733);
  static const Color violet = Color(0xFFA78BFA);
  static const Color cyan = Color(0xFF67E8F9);
  static const Color mint = Color(0xFF6EE7B7);
  static const Color pink = Color(0xFFF472B6);
  static const Color coral = Color(0xFFFB7185);
  static const Color text = Color(0xFFF4F6FF);
  static const Color muted = Color(0xFFAAB5D4);
  static const Color glass = Color(0x24FFFFFF);
  static const Color glassStrong = Color(0x33FFFFFF);
  static const Color glassBorder = Color(0x3DFFFFFF);
  static const Color primaryContainer = Color(0x3D4C1D95);
  static const Color secondaryContainer = Color(0x2A164E63);
}

/// The only app theme: dark Aurora glass.
///
/// Colors are intentionally saturated but kept on a near-black base so text
/// and icons stay legible. Cards use translucency, blur and a hairline border
/// to read as glass rather than flat panels.
final ThemeData larmGlassTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.dark(
    primary: LarmPalette.violet,
    onPrimary: LarmPalette.background,
    secondary: LarmPalette.cyan,
    onSecondary: LarmPalette.background,
    tertiary: LarmPalette.mint,
    onTertiary: LarmPalette.background,
    surface: LarmPalette.background,
    onSurface: LarmPalette.text,
    onSurfaceVariant: LarmPalette.muted,
    outline: LarmPalette.glassBorder,
    outlineVariant: Color(0x2AFFFFFF),
    error: LarmPalette.coral,
    onError: LarmPalette.background,
    primaryContainer: LarmPalette.primaryContainer,
    onPrimaryContainer: Color(0xFFEDE9FE),
    secondaryContainer: LarmPalette.secondaryContainer,
    onSecondaryContainer: Color(0xFFCFFAFE),
    surfaceContainerLowest: LarmPalette.background,
    surfaceContainerLow: LarmPalette.surface,
    surfaceContainer: LarmPalette.surface,
    surfaceContainerHigh: LarmPalette.surface,
    surfaceContainerHighest: LarmPalette.surface,
  ),
  scaffoldBackgroundColor: LarmPalette.background,
  cardTheme: CardThemeData(
    color: LarmPalette.glass,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: LarmPalette.glassBorder),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      color: LarmPalette.text,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    iconTheme: IconThemeData(color: LarmPalette.violet, size: 24),
  ),
  iconTheme: const IconThemeData(color: LarmPalette.violet, size: 24),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: LarmPalette.violet,
    foregroundColor: LarmPalette.background,
    elevation: 8,
    highlightElevation: 12,
  ),
  segmentedButtonTheme: SegmentedButtonThemeData(
    style: ButtonStyle(
      side: WidgetStateProperty.all(
        const BorderSide(color: LarmPalette.glassBorder),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return LarmPalette.primaryContainer;
        }
        return LarmPalette.glass;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return LarmPalette.text;
        return LarmPalette.muted;
      }),
    ),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return LarmPalette.background;
      return LarmPalette.muted;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return LarmPalette.mint;
      return LarmPalette.glassStrong;
    }),
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: LarmPalette.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
      side: BorderSide(color: LarmPalette.glassBorder),
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: LarmPalette.surface,
    surfaceTintColor: Colors.transparent,
    showDragHandle: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      side: BorderSide(color: LarmPalette.glassBorder),
    ),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: LarmPalette.surface,
    contentTextStyle: TextStyle(color: LarmPalette.text),
    behavior: SnackBarBehavior.floating,
  ),
);

/// Clock-hand color for the hybrid hero.
Color larmHandColor(ColorScheme scheme) => scheme.primary;

/// Countdown/progress ring color for the hybrid hero.
Color larmRingColor(ColorScheme scheme) => scheme.secondary;

/// Frosted container used for cards, hero, sheets and list rows.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.blur = 18,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.tint = LarmPalette.glass,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double blur;
  final BorderRadius borderRadius;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final panel = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint,
                tint.withValues(alpha: tint.a / 2),
              ],
            ),
            borderRadius: borderRadius,
            border: Border.all(color: LarmPalette.glassBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (onTap == null) return panel;
    return Semantics(
      button: true,
      child: GestureDetector(onTap: onTap, child: panel),
    );
  }
}

/// Icon inside a tinted glass backplate for high visibility on dark surfaces.
class GlassIcon extends StatelessWidget {
  const GlassIcon({
    super.key,
    required this.icon,
    this.color = LarmPalette.violet,
    this.size = 24,
    this.boxSize = 44,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double boxSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: boxSize,
      height: boxSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.26),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(boxSize / 2),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Icon(icon, color: color, size: size),
    );
  }
}

/// Small translucent badge, e.g. the UTC marker on alarm rows.
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.label,
    this.color = LarmPalette.cyan,
    this.style,
  });

  final String label;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: (style ?? Theme.of(context).textTheme.labelSmall)?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
