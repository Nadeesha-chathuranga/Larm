import 'package:flutter/services.dart';
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

  /// Dedicated slot for the silent "alarm armed" status notice. Kept separate
  /// from fire ids so cancelling a fire never hides the armed indicator.
  static const int armedNotificationId = 0x4C41524D;

  /// Native channel implemented by `MainActivity.kt`. The notifications plugin
  /// can request the full-screen intent permission but cannot query it.
  static const String fsiChannelName = 'com.larm.larm/fsi';
  static const MethodChannel _fsiChannel = MethodChannel(fsiChannelName);

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
      try {
        await androidImpl?.createNotificationChannel(channel);
      } catch (_) {
        // One bad tone channel must not abort scheduling or the armed notice.
      }
    }
    _ready = true;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android {
    try {
      return plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
    } catch (_) {
      // Platform channels are absent in tests/desktop; let callers treat this
      // as "no Android permission flow needed" instead of crashing startup.
      return null;
    }
  }

  /// POST_NOTIFICATIONS (Android 13+; no-op below). Call in context when the
  /// user enables their first alarm.
  static Future<bool?> requestPostNotifications() =>
      _android?.requestNotificationsPermission() ?? Future.value(true);

  /// Exact-alarm status. False means schedules fall back to inexact and the
  /// UI must show the "may delay" banner. No Android plugin (tests/desktop)
  /// is treated as available so the UI doesn't show a false warning.
  static Future<bool> canScheduleExact() async {
    final android = _android;
    if (android == null) return true;
    return (await android.canScheduleExactNotifications()) ?? false;
  }

  /// Deep-links to the system exact-alarm settings (Android 14+ denies by
  /// default). Returns the grant result where the platform reports it.
  static Future<bool?> requestExactAlarms() =>
      _android?.requestExactAlarmsPermission() ?? Future.value(true);

  /// Full-screen intent permission (Android 14+; auto-granted for alarm apps,
  /// revocable). No plugin status query exists, so callers treat null as
  /// "unchanged" and degrade to heads-up + in-app page when denied.
  static Future<bool?> requestFullScreenIntent() =>
      _android?.requestFullScreenIntentPermission() ?? Future.value(true);

  /// Reads the Android 14+ full-screen intent toggle without opening Settings.
  /// Falls back to `true` below Android 14 and when the channel is unavailable
  /// (tests/desktop) so the UI doesn't show a false warning.
  static Future<bool> canUseFullScreenIntent() async {
    try {
      return await _fsiChannel.invokeMethod<bool>('canUseFullScreenIntent') ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// Deep-links directly to Larm's Android 14+ full-screen intent toggle.
  /// The plugin's request method only opens the generic settings list and does
  /// not highlight this app, which made the required toggle hard to find.
  static Future<bool> openFullScreenIntentSettings() async {
    try {
      return await _fsiChannel.invokeMethod<bool>(
            'openFullScreenIntentSettings',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Requests notification, exact-alarm and full-screen permissions in the
  /// product order. Returns false when a fire still cannot be shown reliably,
  /// so callers can fall back to inexact scheduling and tell the user.
  static Future<bool> ensureFirePermissions() async {
    final android = _android;
    if (android == null) return true;
    try {
      final notifications = await requestPostNotifications() ?? true;
      if (!await canScheduleExact()) {
        await requestExactAlarms();
      }
      final exact = await canScheduleExact();
      if (!await canUseFullScreenIntent()) {
        await openFullScreenIntentSettings();
      }
      final fullScreen = await canUseFullScreenIntent();
      return notifications && exact && fullScreen;
    } catch (_) {
      return false;
    }
  }

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
  }) async {
    // `alarmClock` throws outright when exact-alarm permission is denied.
    // Falling back keeps the alarm firing (possibly a little late) instead of
    // silently losing the only scheduled slot.
    bool exact;
    try {
      exact = await canScheduleExact();
    } catch (_) {
      exact = false;
    }
    Future<void> schedule(AndroidScheduleMode mode) => plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: when,
          notificationDetails: details,
          androidScheduleMode: mode,
          payload: payload,
        );

    if (!exact) {
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      return;
    }
    try {
      await schedule(AndroidScheduleMode.alarmClock);
    } catch (_) {
      // Some OEMs reject alarmClock even when canScheduleExact() reports true.
      // Retry rather than dropping the only scheduled slot.
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  /// Shows/updates the silent ongoing notice for the next armed fire.
  /// Failures are swallowed: the alarm schedule itself is the source of truth.
  static Future<void> showArmed({
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    try {
      await plugin.show(
        id: armedNotificationId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: armedDetails()),
      );
    } catch (_) {
      // Status-only notification; never break a real schedule for this.
    }
  }

  static Future<void> cancelArmed() async {
    if (!_ready) return;
    try {
      await plugin.cancel(id: armedNotificationId);
    } catch (_) {
      // Best effort.
    }
  }

  static Future<void> cancel(int id) => plugin.cancel(id: id);

  static Future<List<PendingNotificationRequest>> pending() =>
      plugin.pendingNotificationRequests();
}
