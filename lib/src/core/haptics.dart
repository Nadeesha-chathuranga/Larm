import 'package:flutter/services.dart';

/// Best-effort haptics. Never throws (widget tests have no platform channels).
Future<void> hapticTap() async {
  try {
    await HapticFeedback.lightImpact();
  } catch (_) {
    // No-op: desktop, tests, or missing vibrator.
  }
}

Future<void> hapticConfirm() async {
  try {
    await HapticFeedback.mediumImpact();
  } catch (_) {
    // No-op: desktop, tests, or missing vibrator.
  }
}
