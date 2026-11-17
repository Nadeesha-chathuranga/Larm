import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import 'analog_painter.dart';

/// Hybrid hero: smooth analog face + precise UTC digital readout.
///
/// Larm is UTC-only, so there is no local/secondary clock or swap chip. The
/// countdown ring shows time until the next enabled fire (null when nothing
/// is scheduled). Digits render statically with tabular figures.
class HybridHero extends StatelessWidget {
  const HybridHero({
    super.key,
    required this.dateLabel,
    required this.primaryTime,
    required this.primaryLabel,
    this.ringProgress,
    this.nextLabel,
  });

  final String dateLabel;
  final String primaryTime;
  final String primaryLabel;
  final double? ringProgress;
  final String? nextLabel;

  static const _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      tint: LarmPalette.glassStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(dateLabel, style: textTheme.titleLarge),
              const Spacer(),
              GlassPill(label: primaryLabel, color: LarmPalette.cyan),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnalogClock(
                size: 148,
                tickColor: scheme.onSurface,
                handColor: larmHandColor(scheme),
                secondColor: LarmPalette.mint,
                ringColor: larmRingColor(scheme),
                ringProgress: ringProgress,
                ringWidth: 7,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.globe2,
                          size: 16,
                          color: LarmPalette.cyan,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          primaryLabel,
                          style: textTheme.labelLarge?.copyWith(
                            color: LarmPalette.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        primaryTime,
                        style: textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: _tabular,
                          color: LarmPalette.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (nextLabel != null) ...[
            const SizedBox(height: 12),
            GlassPill(
              label: nextLabel!,
              color: LarmPalette.mint,
              style: textTheme.bodyLarge,
            ),
          ],
        ],
      ),
    );
  }
}
