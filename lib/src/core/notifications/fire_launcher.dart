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
  /// [ringMs] lets the native ring-end receiver close the notification and post
  /// the silent "went off" summary after the configured duration.
  static Future<void> schedule({
    required int id,
    required DateTime when,
    required String? payload,
    int ringMs = 10 * 1000,
  }) async {
    if (payload == null || payload.isEmpty) return;
    final at = when.toUtc().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$fireLauncherKeyPrefix$id',
      jsonEncode({
        'id': id,
        'at': at,
        'payload': payload,
        'ringMs': ringMs,
      }),
    );
    try {
      await _channel.invokeMethod<void>('schedule', {
        'id': id,
        'at': at,
        'payload': payload,
        'ringMs': ringMs,
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
      return await _channel.invokeMethod<bool>(
            'isNotificationActive',
            {'id': id},
          ) ??
          true;
    } catch (_) {
      // Without the channel, assume the notification is doing its job.
      return true;
    }
  }

  /// Starts/stops the low-cost native ticker that refreshes the armed
  /// notification countdown once a minute. No Dart isolate is kept alive.
  static Future<void> scheduleArmedTick({required DateTime when}) async {
    try {
      await _channel.invokeMethod<void>('scheduleArmedTick', {
        'at': when.toUtc().millisecondsSinceEpoch,
      });
    } catch (_) {
      // Status-only; the absolute fire time is still in the shade.
    }
  }

  static Future<void> cancelArmedTick() async {
    try {
      await _channel.invokeMethod<void>('cancelArmedTick');
    } catch (_) {
      // Best effort.
    }
  }

  /// Closes the ringing notification/FSI, leaves the silent "rang at …"
  /// summary, and cancels the pending ring-end alarm so no late summary is
  /// posted after the user already acted.
  static Future<void> finishRing({
    required int id,
    required String payload,
    required DateTime at,
  }) async {
    try {
      await _channel.invokeMethod<void>('finishRing', {
        'id': id,
        'payload': payload,
        'at': at.toUtc().millisecondsSinceEpoch,
      });
    } catch (_) {
      // Best effort: notification timeoutAfter still closes the ring.
    }
  }

  /// Sends Larm to the background after a fired alarm is stopped/snoozed.
  static Future<void> minimize() async {
    try {
      await _channel.invokeMethod<void>('minimize');
    } catch (_) {
      // Best effort on platforms without the activity channel.
    }
  }

  /// Opens Android's sound settings so the user can change the alarm stream;
  /// apps cannot set notification-channel volume programmatically.
  static Future<void> openAlarmVolumeSettings() async {
    try {
      await _channel.invokeMethod<void>('openAlarmVolumeSettings');
    } catch (_) {
      // Best effort.
    }
  }
}
