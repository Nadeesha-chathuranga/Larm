import 'package:flutter_test/flutter_test.dart';
import 'package:larm/src/core/notifications/background_handler.dart';
import 'package:larm/src/core/notifications/scheduler.dart';
import 'package:larm/src/data/models/alarm.dart';
import 'package:larm/src/data/models/larm_timer.dart';
import 'package:larm/src/data/models/settings.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class InMemoryBackend implements AlarmBackend {
  final scheduled = <ScheduledFire>[];
  final cancelled = <int>[];

  @override
  Future<void> schedule(ScheduledFire fire) async {
    scheduled.add(fire);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}

Alarm _alarm({
  String id = 'a1',
  bool enabled = true,
  int hour = 8,
  int minute = 0,
  int repeat = AlarmRepeat.daily,
  bool isUtc = false,
}) {
  return Alarm(
    id: id,
    title: 'Morning',
    isUtc: isUtc,
    hour: hour,
    minute: minute,
    repeat: repeat,
    days: List<bool>.filled(7, false),
    enabled: enabled,
    soundId: 'glass_chime',
    vibId: 'short',
    createdAtUtc: DateTime.utc(2026, 1, 1),
  );
}

LarmTimer _timer({
  String id = 't1',
  int status = TimerStatus.running,
  DateTime? targetUtc,
}) {
  return LarmTimer(
    id: id,
    title: 'Pasta',
    durationSec: 600,
    remainingSec: 600,
    status: status,
    targetUtc: targetUtc,
    enabled: true,
  );
}

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  group('stable notification ids', () {
    test('positive 31-bit, stable, distinct per entry and namespace', () {
      final a1 = AlarmScheduler.notificationIdForAlarm('a1');
      final a1Again = AlarmScheduler.notificationIdForAlarm('a1');
      final a2 = AlarmScheduler.notificationIdForAlarm('a2');
      final t1 = AlarmScheduler.notificationIdForTimer('a1');
      for (final id in [a1, a2, t1]) {
        expect(id, greaterThan(0));
        expect(id, lessThan(0x80000000));
      }
      expect(a1Again, a1);
      expect(a2, isNot(a1));
      expect(t1, isNot(a1));
    });
  });

  group('syncAlarm', () {
    test('disabled alarm cancels slot and schedules nothing', () async {
      final backend = InMemoryBackend();
      final outcome = await AlarmScheduler(backend: backend).syncAlarm(
        _alarm(enabled: false),
        Settings.defaults(),
        now: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(outcome, SyncOutcome.cancelled);
      expect(
          backend.cancelled, [AlarmScheduler.notificationIdForAlarm('a1')]);
      expect(backend.scheduled, isEmpty);
    });

    test('enabled daily alarm schedules next occurrence (follow channel)', () async {
      final backend = InMemoryBackend();
      final outcome = await AlarmScheduler(backend: backend).syncAlarm(
        _alarm(),
        Settings.defaults(),
        now: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(outcome, SyncOutcome.scheduled);
      final fire = backend.scheduled.single;
      expect(fire.id, AlarmScheduler.notificationIdForAlarm('a1'));
      expect(fire.when, tz.TZDateTime.utc(2026, 9, 17, 8, 0));
      expect(fire.payload, 'alarm:a1');
      expect(fire.details.android?.channelId, 'larm_tone_glass_chime_v2');
      expect(fire.details.android?.fullScreenIntent, isTrue);
      expect(fire.details.android?.actions?.length, 2);
    });

    test('override mode picks bypass channel', () async {
      final backend = InMemoryBackend();
      await AlarmScheduler(backend: backend).syncAlarm(
        _alarm(),
        Settings.defaults().copyWith(soundMode: 1),
        now: DateTime.utc(2026, 9, 17, 7, 0),
      );
      final fire = backend.scheduled.single;
      expect(fire.details.android?.channelId, 'larm_override_v2');
      expect(fire.details.android?.channelBypassDnd, isTrue);
    });

    test('system sound falls back to the default follow channel', () async {
      final backend = InMemoryBackend();
      final alarm = _alarm()..soundId = 'system';
      await AlarmScheduler(backend: backend).syncAlarm(
        alarm,
        Settings.defaults(),
        now: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(backend.scheduled.single.details.android?.channelId,
          'larm_follow_v2');
    });

    test('empty title falls back to Alarm', () async {
      final backend = InMemoryBackend();
      final alarm = _alarm()..title = '';
      await AlarmScheduler(backend: backend).syncAlarm(
        alarm,
        Settings.defaults(),
        now: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(backend.scheduled.single.title, 'Alarm');
    });

    test('expired dated one-time cancels without scheduling', () async {
      final backend = InMemoryBackend();
      final alarm = _alarm(repeat: AlarmRepeat.oneTime)
        ..year = 2026
        ..month = 9
        ..day = 15;
      final outcome = await AlarmScheduler(backend: backend).syncAlarm(
        alarm,
        Settings.defaults(),
        now: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(outcome, SyncOutcome.expired);
      expect(backend.scheduled, isEmpty);
    });
  });

  group('snoozeAlarm', () {
    test('schedules now + snoozeMin in same slot', () async {
      final backend = InMemoryBackend();
      await AlarmScheduler(backend: backend).snoozeAlarm(
        _alarm(),
        Settings.defaults().copyWith(snoozeMin: 10),
        now: DateTime.utc(2026, 9, 17, 7, 0),
        remaining: 2,
      );
      final fire = backend.scheduled.single;
      expect(fire.id, AlarmScheduler.notificationIdForAlarm('a1'));
      expect(fire.when, tz.TZDateTime.utc(2026, 9, 17, 7, 10));
    });

    test('zero remaining schedules nothing', () async {
      final backend = InMemoryBackend();
      await AlarmScheduler(backend: backend).snoozeAlarm(
        _alarm(),
        Settings.defaults(),
        now: DateTime.utc(2026, 9, 17, 7, 0),
        remaining: 0,
      );
      expect(backend.scheduled, isEmpty);
    });
  });

  group('syncTimer', () {
    test('running timer with future target schedules completion', () async {
      final backend = InMemoryBackend();
      final outcome = await AlarmScheduler(backend: backend).syncTimer(
        _timer(targetUtc: DateTime.utc(2026, 9, 17, 8, 0)),
        Settings.defaults(),
        now: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(outcome, SyncOutcome.scheduled);
      final fire = backend.scheduled.single;
      expect(fire.id, AlarmScheduler.notificationIdForTimer('t1'));
      expect(fire.payload, 'timer:t1');
    });

    test('paused timer cancels', () async {
      final backend = InMemoryBackend();
      final outcome = await AlarmScheduler(backend: backend).syncTimer(
        _timer(status: TimerStatus.paused),
        Settings.defaults(),
        now: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(outcome, SyncOutcome.cancelled);
      expect(backend.scheduled, isEmpty);
    });

    test('past target is expired', () async {
      final backend = InMemoryBackend();
      final outcome = await AlarmScheduler(backend: backend).syncTimer(
        _timer(targetUtc: DateTime.utc(2026, 9, 17, 6, 0)),
        Settings.defaults(),
        now: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(outcome, SyncOutcome.expired);
    });
  });

  group('syncAll', () {
    test('aggregates counts across entries', () async {
      final backend = InMemoryBackend();
      final result = await AlarmScheduler(backend: backend).syncAll(
        alarms: [_alarm(id: 'on'), _alarm(id: 'off', enabled: false)],
        timers: [_timer(targetUtc: DateTime.utc(2026, 9, 17, 8, 0))],
        settings: Settings.defaults(),
        now: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(result.scheduled, 2);
      expect(result.cancelled, 1);
      expect(result.expired, 0);
    });
  });

  group('parseAlarmAction', () {
    test('parses stop/snooze, rejects junk', () {
      expect(parseAlarmAction('stop_abc'), (kind: 'stop', id: 'abc'));
      expect(parseAlarmAction('snooze_abc'), (kind: 'snooze', id: 'abc'));
      expect(parseAlarmAction(null), isNull);
      expect(parseAlarmAction('tap'), isNull);
      expect(parseAlarmAction('stop_'), isNull);
      expect(parseAlarmAction('launch_abc'), isNull);
    });
  });
}
