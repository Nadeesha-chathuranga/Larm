import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../motion.dart';

/// Pure Black: a true-black base with restrained cyan/white accents.
/// Glows are deliberately faint so glass panels stay crisp on OLED screens.
abstract final class LarmPalette {
  static const Color background = Color(0xFF000000);
  static const Color backgroundDeep = Color(0xFF000000);
  static const Color surface = Color(0xFF0A0C10);

  /// Ice-white accent that replaces the old violet/mint/pink highlights.
  static const Color violet = Color(0xFFE6F6FF);
  static const Color purple = Color(0xFFBFE6FF);
  static const Color cyan = Color(0xFF5FE3FF);
  static const Color mint = Color(0xFFB9F2FF);
  static const Color pink = Color(0xFFDCEEFF);
  static const Color amber = Color(0xFFFFFFFF);

  /// Kept only for destructive/error semantics; never used decoratively.
  static const Color coral = Color(0xFFFF6B7A);

  static const Color text = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF93A2B5);

  static const Color glass = Color(0x12FFFFFF);
  static const Color glassStrong = Color(0x1FFFFFFF);
  static const Color glassBorder = Color(0x3AFFFFFF);
  static const Color primaryContainer = Color(0x1A163B47);
  static const Color secondaryContainer = Color(0x1A102A33);

  /// Signature left-to-right ice/cyan sweep used on digits and the add button.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [violet, cyan, mint],
    stops: [0.0, 0.55, 1.0],
  );

  /// Restrained white/cyan gradient for headings and primary actions.
  static const LinearGradient hotGradient = LinearGradient(
    colors: [Colors.white, cyan, violet],
  );

  static const LinearGradient sunsetGradient = LinearGradient(
    colors: [Colors.white, violet, cyan],
  );
}

/// The only app theme: pure-black dark glass with minimal cyan accents.
final ThemeData larmGlassTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.dark(
    primary: LarmPalette.cyan,
    onPrimary: LarmPalette.backgroundDeep,
    secondary: LarmPalette.violet,
    onSecondary: LarmPalette.backgroundDeep,
    tertiary: LarmPalette.mint,
    onTertiary: LarmPalette.backgroundDeep,
    surface: LarmPalette.background,
    onSurface: LarmPalette.text,
    onSurfaceVariant: LarmPalette.muted,
    outline: LarmPalette.glassBorder,
    outlineVariant: Color(0x24FFFFFF),
    error: LarmPalette.coral,
    onError: LarmPalette.backgroundDeep,
    primaryContainer: LarmPalette.primaryContainer,
    onPrimaryContainer: Colors.white,
    secondaryContainer: LarmPalette.secondaryContainer,
    onSecondaryContainer: Colors.white,
    surfaceContainerLowest: LarmPalette.backgroundDeep,
    surfaceContainerLow: LarmPalette.surface,
    surfaceContainer: LarmPalette.surface,
    surfaceContainerHigh: LarmPalette.surface,
    surfaceContainerHighest: LarmPalette.surface,
  ),
  // The near-invisible backdrop lives behind every route (LarmApp.builder).
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
    backgroundColor: LarmPalette.cyan,
    foregroundColor: LarmPalette.backgroundDeep,
    elevation: 2,
    highlightElevation: 4,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: LarmPalette.cyan,
      foregroundColor: LarmPalette.backgroundDeep,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  ),
  // Forms and chips stay visibly dark on the new alarm/editor page.
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0x0AFFFFFF),
    labelStyle: const TextStyle(color: LarmPalette.muted),
    floatingLabelStyle: const TextStyle(color: LarmPalette.cyan),
    border: const OutlineInputBorder(
      borderSide: BorderSide(color: LarmPalette.glassBorder),
    ),
    enabledBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: LarmPalette.glassBorder),
    ),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: LarmPalette.cyan, width: 1.5),
    ),
    errorBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: LarmPalette.coral),
    ),
  ),
  chipTheme: ChipThemeData(
    brightness: Brightness.dark,
    backgroundColor: LarmPalette.glass,
    selectedColor: LarmPalette.primaryContainer,
    side: const BorderSide(color: LarmPalette.glassBorder),
    labelStyle: const TextStyle(color: LarmPalette.text),
    secondaryLabelStyle: const TextStyle(color: LarmPalette.cyan),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
  ),
  canvasColor: LarmPalette.backgroundDeep,
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
      if (states.contains(WidgetState.selected)) return LarmPalette.cyan;
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

/// Barely-there cyan light behind every route.
///
/// Respects "remove animations" and never intercepts input. Two faint radial
/// gradients on a true-black canvas replace the old five-orb Aurora wash.
class AuroraBackdrop extends StatefulWidget {
  const AuroraBackdrop({super.key});

  @override
  State<AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends State<AuroraBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
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
              color.withValues(alpha: alpha * 0.4),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.4, 1.0],
          ).createShader(rect)
          ..blendMode = BlendMode.screen,
      );
    }

    orb(
      0.86 + 0.03 * math.cos(phase),
      0.06 + 0.02 * math.sin(phase * 0.8),
      w * 0.70,
      LarmPalette.cyan,
      0.06,
    );
    orb(
      0.08 + 0.02 * math.sin(phase * 0.7),
      0.92 + 0.02 * math.cos(phase),
      w * 0.65,
      LarmPalette.violet,
      0.035,
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}

/// Gradient text with a very soft halo. The underlying [Text] keeps all
/// semantics and finders, so existing widget tests are unaffected.
class NeonText extends StatelessWidget {
  const NeonText(
    this.text, {
    super.key,
    required this.style,
    this.gradient = LarmPalette.brandGradient,
    this.glow = LarmPalette.cyan,
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
            Shadow(color: glow.withValues(alpha: 0.25), blurRadius: 14),
            Shadow(color: glow.withValues(alpha: 0.10), blurRadius: 5),
          ],
        ),
      ),
    );
  }
}

/// Frosted container with a restrained hairline edge and optional soft bloom.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.blur = 20,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.tint = LarmPalette.glass,
    this.accent = LarmPalette.cyan,
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
            accent.withValues(alpha: 0.28),
            LarmPalette.glassBorder,
            accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: borderRadius,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.10),
                  blurRadius: 20,
                  spreadRadius: -8,
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
                    tint.withValues(alpha: tint.a * 0.4),
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

/// Icon inside a subtle translucent backplate.
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
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.05),
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.12),
                  blurRadius: 14,
                  spreadRadius: -4,
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
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 10),
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

/// Ice/cyan add button with a soft halo. Keeps [Tooltip] so existing
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
                color: Color(0x335FE3FF),
                blurRadius: 18,
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 12,
                offset: Offset(0, 6),
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
