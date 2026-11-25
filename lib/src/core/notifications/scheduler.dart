import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/time/clock.dart';
import '../../data/models/alarm.dart';
import '../../data/models/larm_timer.dart';
import '../../data/models/settings.dart';
import 'channels.dart';
import 'fire_launcher.dart';
import 'service.dart';

/// One scheduled OS notification. Backend-agnostic so the scheduler is
/// unit-testable without platform channels.
class ScheduledFire {
  const ScheduledFire({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.details,
    this.payload,
  });

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime when;
  final NotificationDetails details;
  final String? payload;
}

/// Platform scheduling sink. Production impl delegates to [NotificationService].
abstract class AlarmBackend {
  Future<void> schedule(ScheduledFire fire);
  Future<void> cancel(int id);

  /// Optional status-notification hooks. Default no-ops keep test backends
  /// simple; the production backend shows a silent "armed" notice.
  Future<void> updateArmed({required String title, required String body}) async {}
  Future<void> clearArmed() async {}
}

class PluginBackend implements AlarmBackend {
  @override
  Future<void> schedule(ScheduledFire fire) async {
    await NotificationService.scheduleFire(
      id: fire.id,
      title: fire.title,
      body: fire.body,
      when: fire.when,
      details: fire.details,
      payload: fire.payload,
    );
    // Android suppresses FSI while the screen is on, so pair the notification
    // with a direct trigger-page launch alarm. Same id keeps the slots aligned.
    await FireLauncher.schedule(
      id: fire.id,
      when: fire.when,
      payload: fire.payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await NotificationService.cancel(id);
    await FireLauncher.cancel(id);
  }

  @override
  Future<void> updateArmed({required String title, required String body}) =>
      NotificationService.showArmed(title: title, body: body);

  @override
  Future<void> clearArmed() => NotificationService.cancelArmed();
}

/// Riverpod access to the scheduler. Tests override the backend.
final schedulerProvider = Provider<AlarmScheduler>(
  (_) => AlarmScheduler(backend: PluginBackend()),
);

/// Outcome of a sync, for UI banners and tests.
enum SyncOutcome { scheduled, cancelled, expired }

/// Maps domain entries to exact OS schedules.
///
/// Invariants:
/// * one pending schedule per entry max (next occurrence only);
/// * notification ids are stable across restarts (FNV-1a, 31-bit);
/// * disabled/expired entries always cancel their slot.
class AlarmScheduler {
  AlarmScheduler({required this._backend});

  final AlarmBackend _backend;

  /// Stable 31-bit positive id for an alarm slot. Dart's [String.hashCode]
  /// is not stable across runs, so FNV-1a is used instead.
  static int notificationIdForAlarm(String alarmId) =>
      _stableId('alarm:$alarmId');

  /// Stable 31-bit positive id for a timer-completion slot.
  static int notificationIdForTimer(String timerId) =>
      _stableId('timer:$timerId');

  static int _stableId(String key) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < key.length; i++) {
      hash ^= key.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    final id = hash & 0x7fffffff;
    return id == 0 ? 1 : id;
  }

  bool _override(Settings settings) => settings.soundMode == 1;

  String _timeBody(tz.TZDateTime when, Settings settings) =>
      fmtTime(when, use24h: settings.timeFormat == 1);

  NotificationDetails _details({
    required bool overrideMode,
    required String entryId,
    required String payload,
    required String soundId,
    required String vibrationId,
  }) => NotificationDetails(
    android: alarmDetails(
      overrideMode: overrideMode,
      entryId: entryId,
      payload: payload,
      soundId: soundId,
      vibrationId: vibrationId,
    ),
  );

  /// Cancels then (re)schedules an alarm's next occurrence. Call after every
  /// mutation, permission grant, and cold start (boot recovery).
  Future<SyncOutcome> syncAlarm(
    Alarm alarm,
    Settings settings, {
    required DateTime now,
  }) async {
    final id = notificationIdForAlarm(alarm.id);
    await _backend.cancel(id);
    if (!alarm.enabled) return SyncOutcome.cancelled;
    final next = nextOccurrence(alarm, fromUtc: now);
    if (next == null) return SyncOutcome.expired;
    await _backend.schedule(
      ScheduledFire(
        id: id,
        title: alarm.title.isEmpty ? 'Alarm' : alarm.title,
        body: _timeBody(next, settings),
        when: next,
        details: _details(
          overrideMode: _override(settings),
          entryId: alarm.id,
          payload: alarmPayload(alarm.id),
          soundId: settings.defaultSoundId,
          vibrationId: settings.defaultVibId,
        ),
        payload: alarmPayload(alarm.id),
      ),
    );
    return SyncOutcome.scheduled;
  }

  /// Snoozes to now + [Settings.snoozeMin], reusing the alarm's slot so the
  /// original fire is replaced. [remaining] is enforced by the caller (M5 UI).
  Future<void> snoozeAlarm(
    Alarm alarm,
    Settings settings, {
    required DateTime now,
    required int remaining,
  }) async {
    if (remaining <= 0) return;
    final when = tz.TZDateTime.from(
      now.toUtc(),
      tz.UTC,
    ).add(Duration(minutes: settings.snoozeMin));
    await _backend.schedule(
      ScheduledFire(
        id: notificationIdForAlarm(alarm.id),
        title: alarm.title.isEmpty ? 'Alarm' : alarm.title,
        body: 'Snoozed · ${_timeBody(when, settings)}',
        when: when,
        details: _details(
          overrideMode: _override(settings),
          entryId: alarm.id,
          payload: alarmPayload(alarm.id),
          soundId: settings.defaultSoundId,
          vibrationId: settings.defaultVibId,
        ),
        payload: alarmPayload(alarm.id),
      ),
    );
  }

  /// Schedules a running timer's completion; cancels otherwise. This is what
  /// guarantees timer completion while the app is killed.
  Future<SyncOutcome> syncTimer(
    LarmTimer timer,
    Settings settings, {
    required DateTime now,
  }) async {
    final id = notificationIdForTimer(timer.id);
    await _backend.cancel(id);
    final target = timer.targetUtc;
    if (timer.status != TimerStatus.running || target == null) {
      return SyncOutcome.cancelled;
    }
    if (!target.toUtc().isAfter(now.toUtc())) return SyncOutcome.expired;
    final when = tz.TZDateTime.from(target.toUtc(), tz.UTC);
    await _backend.schedule(
      ScheduledFire(
        id: id,
        title: timer.title.isEmpty ? 'Timer' : timer.title,
        body: 'Done',
        when: when,
        details: _details(
          overrideMode: _override(settings),
          entryId: timer.id,
          payload: timerPayload(timer.id),
          soundId: settings.defaultSoundId,
          vibrationId: settings.defaultVibId,
        ),
        payload: timerPayload(timer.id),
      ),
    );
    return SyncOutcome.scheduled;
  }

  /// Earliest enabled fire, used for the silent "alarm armed" status notice.
  ({tz.TZDateTime when, String label})? _nextArmed({
    required List<Alarm> alarms,
    required List<LarmTimer> timers,
    required Settings settings,
    required DateTime now,
  }) {
    final use24h = settings.timeFormat == 1;
    ({tz.TZDateTime when, String label})? best;

    void consider(tz.TZDateTime when, String label) {
      if (best == null || when.isBefore(best!.when)) {
        best = (when: when, label: label);
      }
    }

    for (final alarm in alarms) {
      if (!alarm.enabled) continue;
      final next = nextOccurrence(alarm, fromUtc: now);
      if (next == null) continue;
      final name = alarm.title.trim().isEmpty ? 'Alarm' : alarm.title.trim();
      consider(
        next,
        '$name · ${fmtDateTime(next, use24h: use24h)} UTC',
      );
    }
    for (final timer in timers) {
      final target = timer.targetUtc;
      if (timer.status != TimerStatus.running ||
          target == null ||
          !target.toUtc().isAfter(now.toUtc())) {
        continue;
      }
      final when = tz.TZDateTime.from(target.toUtc(), tz.UTC);
      final name = timer.title.trim().isEmpty ? 'Timer' : timer.title.trim();
      consider(
        when,
        '$name · ${fmtDateTime(when, use24h: use24h)} UTC',
      );
    }
    return best;
  }

  /// Refreshes the visible status notice from the full stored state. Call after
  /// any mutation so the shade never shows a stale or missing armed alarm.
  Future<void> refreshArmed({
    required List<Alarm> alarms,
    required List<LarmTimer> timers,
    required Settings settings,
    required DateTime now,
  }) async {
    final next = _nextArmed(
      alarms: alarms,
      timers: timers,
      settings: settings,
      now: now,
    );
    if (next == null) {
      await _backend.clearArmed();
      return;
    }
    await _backend.updateArmed(title: 'Alarm armed', body: next.label);
  }

  /// Recomputes every slot. Runs on cold start (covers reboot, update, and
  /// permission-revocation recovery) and after settings changes.
  Future<({int scheduled, int cancelled, int expired})> syncAll({
    required List<Alarm> alarms,
    required List<LarmTimer> timers,
    required Settings settings,
    required DateTime now,
  }) async {
    var scheduled = 0;
    var cancelled = 0;
    var expired = 0;
    for (final alarm in alarms) {
      switch (await syncAlarm(alarm, settings, now: now)) {
        case SyncOutcome.scheduled:
          scheduled++;
        case SyncOutcome.cancelled:
          cancelled++;
        case SyncOutcome.expired:
          expired++;
      }
    }
    for (final timer in timers) {
      switch (await syncTimer(timer, settings, now: now)) {
        case SyncOutcome.scheduled:
          scheduled++;
        case SyncOutcome.cancelled:
          cancelled++;
        case SyncOutcome.expired:
          expired++;
      }
    }
    await refreshArmed(
      alarms: alarms,
      timers: timers,
      settings: settings,
      now: now,
    );
    return (scheduled: scheduled, cancelled: cancelled, expired: expired);
  }
}
