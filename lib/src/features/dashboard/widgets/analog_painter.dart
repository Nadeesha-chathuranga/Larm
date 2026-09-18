import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/motion.dart';

/// Minimalist analog face with smooth hands and an optional countdown ring.
///
/// Reads the tick time in [paint] so a parent [Ticker] only repaints this
/// canvas (kept behind a [RepaintBoundary] by [AnalogClock]).
class AnalogPainter extends CustomPainter {
  AnalogPainter({
    required this.now,
    required this.tickColor,
    required this.handColor,
    required this.secondColor,
    required this.ringColor,
    this.ringProgress,
    this.ringWidth = 5,
  });

  final DateTime now;
  final Color tickColor;
  final Color handColor;
  final Color secondColor;
  final Color ringColor;

  /// 0..1 countdown ring around the face; null hides it.
  final double? ringProgress;

  /// Ring stroke width (hero uses a bolder ring).
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final progress = ringProgress;
    if (progress != null) {
      final ring = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 3),
        -math.pi / 2,
        (progress.clamp(0.0, 1.0)) * math.pi * 2,
        false,
        ring,
      );
    }

    final faceRadius = radius - 10;
    for (var i = 0; i < 60; i++) {
      final hour = i % 5 == 0;
      final a = i * math.pi / 30;
      final p1 = Offset(
        center.dx + math.cos(a) * (faceRadius - (hour ? 10 : 5)),
        center.dy + math.sin(a) * (faceRadius - (hour ? 10 : 5)),
      );
      final p2 = Offset(
        center.dx + math.cos(a) * faceRadius,
        center.dy + math.sin(a) * faceRadius,
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = tickColor.withValues(alpha: hour ? 0.9 : 0.35)
          ..strokeWidth = hour ? 3 : 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Smooth angles (include fractional seconds/minutes).
    final seconds = now.second + now.millisecond / 1000;
    final minutes = now.minute + seconds / 60;
    final hours = (now.hour % 12) + minutes / 60;

    void hand(double angle, double length, double width, Color color) {
      final tip = Offset(
        center.dx + math.cos(angle - math.pi / 2) * length,
        center.dy + math.sin(angle - math.pi / 2) * length,
      );
      canvas.drawLine(
        center,
        tip,
        Paint()..color = color..strokeWidth = width..strokeCap = StrokeCap.round,
      );
    }

    hand(hours * math.pi / 6, faceRadius * 0.5, 6, handColor);
    hand(minutes * math.pi / 30, faceRadius * 0.75, 4, handColor);
    hand(seconds * math.pi / 30, faceRadius * 0.85, 2, secondColor);

    canvas.drawCircle(center, 4, Paint()..color = secondColor);
  }

  @override
  bool shouldRepaint(AnalogPainter old) =>
      old.now != now ||
      old.ringProgress != ringProgress ||
      old.ringWidth != ringWidth ||
      old.tickColor != tickColor ||
      old.handColor != handColor ||
      old.secondColor != secondColor ||
      old.ringColor != ringColor;
}

/// Self-ticking analog clock. Only this widget rebuilds each frame; the rest
/// of the tree is untouched (60fps-safe with a [RepaintBoundary]).
class AnalogClock extends StatefulWidget {
  const AnalogClock({
    super.key,
    required this.size,
    required this.tickColor,
    required this.handColor,
    required this.secondColor,
    required this.ringColor,
    this.ringProgress,
    this.ringWidth = 5,
  });

  final double size;
  final Color tickColor;
  final Color handColor;
  final Color secondColor;
  final Color ringColor;
  final double? ringProgress;
  final double ringWidth;

  @override
  State<AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<AnalogClock>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduce-motion: static face instead of a 60fps ticker.
    final shouldRun = motionEnabled(context);
    if (shouldRun == _running) return;
    _running = shouldRun;
    if (_running) {
      _ticker.start();
    } else {
      _ticker.stop();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: AnalogPainter(
          now: DateTime.now(),
          tickColor: widget.tickColor,
          handColor: widget.handColor,
          secondColor: widget.secondColor,
          ringColor: widget.ringColor,
          ringProgress: widget.ringProgress,
          ringWidth: widget.ringWidth,
        ),
      ),
    );
  }
}
