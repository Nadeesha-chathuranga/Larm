import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prefs.dart';

/// Companion exact alarm for locked-screen fires.
///
/// Android deliberately does not launch a full-screen intent while the user is
/// actively using the device: the alarm is downgraded to a heads-up popup,
/// which is what Larm wants for unlocked phones. This second, app-owned alarm
/// fires at the same UTC instant and opens `/trigger` only when the screen is
/// off or the keyguard is locked. The notification remains the audio/vibration
/// source in every state; duplicate callbacks are deduped by `FireHandoff`.
class FireLauncher {
  FireLauncher._();

  static const String channelName = 'com.larm.larm/fire_launcher';
  static const MethodChannel _channel = MethodChannel(channelName);

  /// Schedules the native launch alarm and persists it for reboot recovery.
  static Future<void> schedule({
    required int id,
    required DateTime when,
    required String? payload,
  }) async {
    if (payload == null || payload.isEmpty) return;
    final at = when.toUtc().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$fireLauncherKeyPrefix$id',
      jsonEncode({'id': id, 'at': at, 'payload': payload}),
    );
    try {
      await _channel.invokeMethod<void>('schedule', {
        'id': id,
        'at': at,
        'payload': payload,
      });
    } catch (_) {
      // Best effort: the persisted entry still lets the boot receiver recover.
    }
  }

  /// Cancels the launch alarm and removes the persisted reboot entry.
  static Future<void> cancel(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$fireLauncherKeyPrefix$id');
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } catch (_) {
      // Best effort: stale launch alarms are harmless on reboot.
    }
  }

  /// Epoch millis written by the native exact-alarm receiver at fire time.
  static Future<DateTime?> lastFireAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt('${fireLauncherKeyPrefix}last_fire_at');
      return value == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  /// Whether the fire notification is still posting its looping tone.
  ///
  /// Some OEMs dismiss the notification as soon as a full-screen intent is
  /// consumed. In that case `TriggerPage` continues the tone in-app so the
  /// audible ring still lasts the full window.
  static Future<bool> isNotificationActive(int id) async {
    try {
      return await _channel.invokeMethod<bool>('isNotificationActive', {'id': id}) ??
          true;
    } catch (_) {
      // Without the channel, assume the notification is doing its job.
      return true;
    }
  }
}
