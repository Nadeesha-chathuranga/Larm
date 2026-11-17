import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../motion.dart';

/// Aurora 2.0: near-black space base with saturated violet, cyan, mint, pink
/// and amber light. Colors stay bright enough to glow on dark glass.
abstract final class LarmPalette {
  static const Color background = Color(0xFF050614);
  static const Color backgroundDeep = Color(0xFF02030B);
  static const Color surface = Color(0xFF121936);

  static const Color violet = Color(0xFFB388FF);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color cyan = Color(0xFF4DE8FF);
  static const Color mint = Color(0xFF5CFFC2);
  static const Color pink = Color(0xFFFF6EC7);
  static const Color amber = Color(0xFFFFD166);
  static const Color coral = Color(0xFFFF6B8A);

  static const Color text = Color(0xFFF7F8FF);
  static const Color muted = Color(0xFFACB8DE);

  static const Color glass = Color(0x2AFFFFFF);
  static const Color glassStrong = Color(0x3DFFFFFF);
  static const Color glassBorder = Color(0x59FFFFFF);
  static const Color primaryContainer = Color(0x4D4C1D95);
  static const Color secondaryContainer = Color(0x3A164E63);

  /// Signature left-to-right aurora sweep used on digits and the add button.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [violet, cyan, mint],
    stops: [0.0, 0.55, 1.0],
  );

  /// Hotter accent for alerts and primary call-to-action surfaces.
  static const LinearGradient hotGradient = LinearGradient(
    colors: [pink, violet, cyan],
  );

  static const LinearGradient sunsetGradient = LinearGradient(
    colors: [amber, pink, violet],
  );
}

/// The only app theme: dark Aurora glass with neon accents.
final ThemeData larmGlassTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.dark(
    primary: LarmPalette.violet,
    onPrimary: LarmPalette.backgroundDeep,
    secondary: LarmPalette.cyan,
    onSecondary: LarmPalette.backgroundDeep,
    tertiary: LarmPalette.mint,
    onTertiary: LarmPalette.backgroundDeep,
    surface: LarmPalette.background,
    onSurface: LarmPalette.text,
    onSurfaceVariant: LarmPalette.muted,
    outline: LarmPalette.glassBorder,
    outlineVariant: Color(0x33FFFFFF),
    error: LarmPalette.coral,
    onError: LarmPalette.backgroundDeep,
    primaryContainer: LarmPalette.primaryContainer,
    onPrimaryContainer: Color(0xFFF3E8FF),
    secondaryContainer: LarmPalette.secondaryContainer,
    onSecondaryContainer: Color(0xFFCFFAFE),
    surfaceContainerLowest: LarmPalette.backgroundDeep,
    surfaceContainerLow: LarmPalette.surface,
    surfaceContainer: LarmPalette.surface,
    surfaceContainerHigh: LarmPalette.surface,
    surfaceContainerHighest: LarmPalette.surface,
  ),
  // The animated aurora lives behind every route (see LarmApp.builder).
  scaffoldBackgroundColor: Colors.transparent,
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
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
    ),
    iconTheme: IconThemeData(color: LarmPalette.cyan, size: 24),
  ),
  iconTheme: const IconThemeData(color: LarmPalette.violet, size: 24),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: LarmPalette.violet,
    foregroundColor: LarmPalette.backgroundDeep,
    elevation: 10,
    highlightElevation: 16,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: LarmPalette.violet,
      foregroundColor: LarmPalette.backgroundDeep,
      shadowColor: const Color(0x88B388FF),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
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
      if (states.contains(WidgetState.selected)) {
        return LarmPalette.backgroundDeep;
      }
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
Color larmHandColor(ColorScheme scheme) => LarmPalette.violet;

/// Countdown/progress ring color for the hybrid hero.
Color larmRingColor(ColorScheme scheme) => LarmPalette.cyan;

/// Slow-drifting aurora light behind every route.
///
/// Respects "remove animations" and never intercepts input. The painter is
/// cheap: five radial gradients, repainted only by this widget.
class AuroraBackdrop extends StatefulWidget {
  const AuroraBackdrop({super.key});

  @override
  State<AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends State<AuroraBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (motionEnabled(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _AuroraPainter(_controller.value),
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter(this.t);

  /// 0..1 loop position.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = LarmPalette.backgroundDeep,
    );
    // A faint vertical wash keeps the base from reading as flat black.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [LarmPalette.background, LarmPalette.backgroundDeep],
        ).createShader(Offset.zero & size),
    );

    final w = size.width;
    final h = size.height;
    final phase = t * math.pi * 2;

    void orb(double x, double y, double radius, Color color, double alpha) {
      final center = Offset(x * w, y * h);
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.45),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(rect)
          ..blendMode = BlendMode.screen,
      );
    }

    orb(
      0.14 + 0.05 * math.sin(phase),
      0.12 + 0.04 * math.cos(phase * 0.8),
      w * 0.72,
      LarmPalette.purple,
      0.34,
    );
    orb(
      0.88 + 0.04 * math.cos(phase * 1.1),
      0.10 + 0.05 * math.sin(phase * 0.7),
      w * 0.62,
      LarmPalette.cyan,
      0.28,
    );
    orb(
      0.52 + 0.07 * math.sin(phase * 0.6 + 1),
      0.96 + 0.03 * math.cos(phase),
      w * 0.85,
      LarmPalette.mint,
      0.20,
    );
    orb(
      0.95 + 0.03 * math.sin(phase * 0.9),
      0.72 + 0.05 * math.cos(phase * 1.2),
      w * 0.55,
      LarmPalette.pink,
      0.20,
    );
    orb(
      0.05 + 0.04 * math.cos(phase * 1.3),
      0.78 + 0.04 * math.sin(phase * 0.8),
      w * 0.50,
      LarmPalette.amber,
      0.13,
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}

/// Gradient text with a soft colored halo. Used for the hero clock and empty
/// state headline; the underlying [Text] keeps all semantics and finders.
class NeonText extends StatelessWidget {
  const NeonText(
    this.text, {
    super.key,
    required this.style,
    this.gradient = LarmPalette.brandGradient,
    this.glow = LarmPalette.violet,
  });

  final String text;
  final TextStyle style;
  final Gradient gradient;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: Text(
        text,
        style: style.copyWith(
          color: Colors.white,
          shadows: [
            Shadow(color: glow.withValues(alpha: 0.65), blurRadius: 22),
            Shadow(color: glow.withValues(alpha: 0.35), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}

/// Frosted container with a gradient hairline edge and optional neon bloom.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.blur = 20,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.tint = LarmPalette.glass,
    this.accent = LarmPalette.violet,
    this.glow = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double blur;
  final BorderRadius borderRadius;
  final Color tint;
  final Color accent;
  final bool glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.65),
            LarmPalette.glassBorder,
            accent.withValues(alpha: 0.20),
          ],
        ),
        borderRadius: borderRadius,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 28,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
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
                    tint.withValues(alpha: tint.a * 0.55),
                  ],
                ),
                borderRadius: borderRadius,
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
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

/// Icon inside a translucent, tinted and softly glowing backplate.
class GlassIcon extends StatelessWidget {
  const GlassIcon({
    super.key,
    required this.icon,
    this.color = LarmPalette.violet,
    this.size = 24,
    this.boxSize = 44,
    this.glow = true,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double boxSize;
  final bool glow;

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
            color.withValues(alpha: 0.40),
            color.withValues(alpha: 0.10),
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.70)),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.38),
                  blurRadius: 20,
                  spreadRadius: -3,
                ),
              ]
            : null,
      ),
      child: Icon(icon, color: color, size: size),
    );
  }
}

/// Small luminous badge, e.g. the UTC marker on alarm rows.
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
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.09),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.70)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 14),
        ],
      ),
      child: Text(
        label,
        style: (style ?? Theme.of(context).textTheme.labelSmall)?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Gradient add button with a colored halo. Keeps [Tooltip] so existing
/// `find.byTooltip` tests and accessibility behavior still work.
class NeonFab extends StatelessWidget {
  const NeonFab({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          width: 62,
          height: 62,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LarmPalette.brandGradient,
            boxShadow: [
              BoxShadow(
                color: Color(0x99B388FF),
                blurRadius: 26,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Color(0x664DE8FF),
                blurRadius: 42,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: InkWell(
            onTap: onPressed,
            child: Icon(icon, color: LarmPalette.backgroundDeep, size: 30),
          ),
        ),
      ),
    );
  }
}
