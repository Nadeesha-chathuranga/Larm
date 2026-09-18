import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import 'analog_painter.dart';

/// Hybrid hero: smooth analog face + precise digital readout.
///
/// [primary]/[secondary] are preformatted (time, label) pairs. Tapping the
/// chip swaps local/UTC prominence. [ringProgress] shows the countdown to the
/// next enabled fire (null when nothing is scheduled). Digits render
/// statically with tabular figures (no per-second animation).
class HybridHero extends StatelessWidget {
  const HybridHero({
    super.key,
    required this.dateLabel,
    required this.primaryTime,
    required this.primaryLabel,
    required this.secondaryTime,
    required this.secondaryLabel,
    required this.onSwap,
    this.ringProgress,
    this.nextLabel,
  });

  final String dateLabel;
  final String primaryTime;
  final String primaryLabel;
  final String secondaryTime;
  final String secondaryLabel;
  final VoidCallback onSwap;
  final double? ringProgress;
  final String? nextLabel;

  static const _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateLabel, style: textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnalogClock(
                  size: 148,
                  tickColor: scheme.onSurface,
                  handColor: larmHandColor(scheme),
                  secondColor: scheme.primary,
                  ringColor: larmRingColor(scheme),
                  ringProgress: ringProgress,
                  ringWidth: 7,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primaryLabel,
                        style: textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        primaryTime,
                        style: textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: _tabular,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ActionChip(
                        label: Text(
                          '$secondaryLabel · $secondaryTime',
                          style: const TextStyle(fontFeatures: _tabular),
                        ),
                        onPressed: onSwap,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (nextLabel != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  nextLabel!,
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
