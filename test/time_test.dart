import 'package:flutter_test/flutter_test.dart';
import 'package:larm/src/core/time/clock.dart';
import 'package:larm/src/data/models/alarm.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Alarm _alarm({
  int hour = 8,
  int minute = 0,
  bool isUtc = false,
  int repeat = AlarmRepeat.daily,
  List<bool>? days,
  int? year,
  int? month,
  int? day,
}) {
  return Alarm(
    id: 't',
    title: 'Test',
    isUtc: isUtc,
    hour: hour,
    minute: minute,
    year: year,
    month: month,
    day: day,
    repeat: repeat,
    days: days ?? List<bool>.filled(7, false),
    enabled: true,
    soundId: 'glass_chime',
    vibId: 'short',
    createdAtUtc: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  group('fmtTime', () {
    test('24h pads hour and minute', () {
      expect(fmtTime(DateTime(2026, 1, 1, 8, 5), use24h: true), '08:05');
    });

    test('12h converts midnight and afternoon', () {
      expect(fmtTime(DateTime(2026, 1, 1, 0, 5), use24h: false), '12:05 AM');
      expect(fmtTime(DateTime(2026, 1, 1, 20, 5), use24h: false), '8:05 PM');
    });
  });

  group('nextOccurrence', () {
    test('daily later today stays today', () {
      final from = DateTime.utc(2026, 9, 17, 7, 0);
      final at = nextOccurrence(_alarm(hour: 8), fromLocal: from)!;
      expect(at.day, 17);
      expect(at.hour, 8);
    });

    test('daily past time rolls to tomorrow', () {
      final from = DateTime.utc(2026, 9, 17, 9, 0);
      final at = nextOccurrence(_alarm(hour: 8), fromLocal: from)!;
      expect(at.day, 18);
    });

    test('weekdays skips weekend', () {
      // Saturday 2026-09-19 10:00 UTC.
      final from = DateTime.utc(2026, 9, 19, 10, 0);
      final at = nextOccurrence(
        _alarm(hour: 8, repeat: AlarmRepeat.weekdays),
        fromLocal: from,
      )!;
      expect(at.weekday, DateTime.monday);
      expect(at.day, 21);
    });

    test('custom days picks next selected day', () {
      // Thursday 2026-09-17; only Sunday selected.
      final from = DateTime.utc(2026, 9, 17, 7, 0);
      final days = List<bool>.filled(7, false)..[6] = true;
      final at = nextOccurrence(
        _alarm(hour: 8, repeat: AlarmRepeat.custom, days: days),
        fromLocal: from,
      )!;
      expect(at.weekday, DateTime.sunday);
      expect(at.day, 20);
    });

    test('dated one-time future fires, past returns null', () {
      final future = nextOccurrence(
        _alarm(
            repeat: AlarmRepeat.oneTime, year: 2026, month: 9, day: 20, hour: 8),
        fromLocal: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(future, isNotNull);
      final past = nextOccurrence(
        _alarm(
            repeat: AlarmRepeat.oneTime, year: 2026, month: 9, day: 15, hour: 8),
        fromLocal: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(past, isNull);
    });

    test('UTC fixed across DST', () {
      // America/New_York springs forward 2026-03-08: wall clock loses an hour,
      // the absolute UTC instant of a UTC alarm must not move.
      // Note: Mar 7 07:00 local (EST) is exactly 12:00 UTC, so the strictly-
      // after rule rolls that day's slot to Mar 8.
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      addTearDown(() => tz.setLocalLocation(tz.UTC));
      final before = nextOccurrence(
        _alarm(hour: 12, minute: 0, isUtc: true),
        fromLocal: tz.TZDateTime(tz.local, 2026, 3, 7, 7, 0),
      )!;
      final after = nextOccurrence(
        _alarm(hour: 12, minute: 0, isUtc: true),
        fromLocal: tz.TZDateTime(tz.local, 2026, 3, 9, 7, 0),
      )!;
      expect(before.toUtc(), DateTime.utc(2026, 3, 8, 12, 0));
      expect(after.toUtc(), DateTime.utc(2026, 3, 9, 12, 0));
    });

    test('local daily keeps wall time across DST', () {
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      addTearDown(() => tz.setLocalLocation(tz.UTC));
      final at = nextOccurrence(
        _alarm(hour: 8, minute: 30),
        fromLocal: tz.TZDateTime(tz.local, 2026, 3, 9, 7, 0),
      )!;
      expect(at.hour, 8);
      expect(at.minute, 30);
    });

    test('local vs UTC diverge on travel day', () {
      // Same nominal 08:00: local alarm lands at 08:00 New York wall
      // (12:00 UTC in September, EDT), UTC alarm lands at 08:00 UTC.
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      addTearDown(() => tz.setLocalLocation(tz.UTC));
      final from = tz.TZDateTime(tz.local, 2026, 9, 17, 7, 0);
      final local = nextOccurrence(_alarm(hour: 8), fromLocal: from)!;
      final utc = nextOccurrence(
          _alarm(hour: 8, isUtc: true), fromLocal: from)!;
      expect(local.toUtc().hour, 12);
      expect(utc.toUtc().hour, 8);
    });
  });
}
