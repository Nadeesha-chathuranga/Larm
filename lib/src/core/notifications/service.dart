import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'background_handler.dart';
import 'channels.dart';

/// Notification plugin bootstrap plus exact-scheduling primitives.
///
/// Permission UX order (M2): POST → exact → full-screen intent → battery-opt
/// education → notification-policy access (only on override opt-in).
/// UI explainer sheets land with the dashboard (M3); this class only exposes
/// the platform calls so they are unit-mockable via [AlarmBackend].
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  /// Whether [init] completed without throwing.
  static bool get isReady => _ready;

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
    await plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onBgAction,
    );
    final androidImpl = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // M6 migration: v1 channels are immutable; delete and recreate as v2.
    for (final legacy in legacyChannelIds) {
      try {
        await androidImpl?.deleteNotificationChannel(channelId: legacy);
      } catch (_) {
        // Channel may not exist: ignore.
      }
    }
    for (final channel in v2Channels()) {
      await androidImpl?.createNotificationChannel(channel);
    }
    _ready = true;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// POST_NOTIFICATIONS (Android 13+; no-op below). Call in context when the
  /// user enables their first alarm.
  static Future<bool?> requestPostNotifications() =>
      _android?.requestNotificationsPermission() ?? Future.value(true);

  /// Exact-alarm status. False means schedules fall back to inexact and the
  /// UI must show the "may delay" banner.
  static Future<bool> canScheduleExact() async =>
      (await _android?.canScheduleExactNotifications()) ?? false;

  /// Deep-links to the system exact-alarm settings (Android 14+ denies by
  /// default). Returns the grant result where the platform reports it.
  static Future<bool?> requestExactAlarms() =>
      _android?.requestExactAlarmsPermission() ?? Future.value(true);

  /// Full-screen intent permission (Android 14+; auto-granted for alarm apps,
  /// revocable). No plugin status query exists, so callers treat null as
  /// "unchanged" and degrade to heads-up + in-app page when denied.
  static Future<bool?> requestFullScreenIntent() =>
      _android?.requestFullScreenIntentPermission() ?? Future.value(true);

  /// DND-bypass channel support. Request only when the user opts into
  /// `alwaysOverride`; creating a `bypassDnd` channel without access silently
  /// creates it *without* bypass.
  static Future<bool> hasPolicyAccess() async =>
      (await _android?.hasNotificationPolicyAccess()) ?? false;

  static Future<bool?> requestPolicyAccess() =>
      _android?.requestNotificationPolicyAccess() ?? Future.value(false);

  /// Schedules one fire at the highest priority (`setAlarmClock`). Only the
  /// next occurrence per entry is ever scheduled (Samsung 500-alarm guard).
  static Future<void> scheduleFire({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required NotificationDetails details,
    String? payload,
  }) {
    return plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: payload,
    );
  }

  static Future<void> cancel(int id) => plugin.cancel(id: id);

  static Future<List<PendingNotificationRequest>> pending() =>
      plugin.pendingNotificationRequests();
}
