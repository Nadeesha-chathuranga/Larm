import 'package:flutter_test/flutter_test.dart';
import 'package:larm/src/core/time/clock.dart';
import 'package:larm/src/data/models/alarm.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Alarm _alarm({
  int hour = 8,
  int minute = 0,
  // Kept for Hive schema stability; the UTC-only app ignores this legacy flag.
  bool isUtc = true,
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
    test('always uses 24h and pads hour and minute', () {
      expect(fmtTime(DateTime.utc(2026, 1, 1, 8, 5)), '08:05');
      expect(fmtTime(DateTime.utc(2026, 1, 1, 0, 5)), '00:05');
      expect(fmtTime(DateTime.utc(2026, 1, 1, 20, 5)), '20:05');
    });

    test('fmtUtcTime formats the UTC view', () {
      expect(fmtUtcTime(DateTime.utc(2026, 9, 17, 13, 40)), '13:40');
    });
  });

  group('fmtDateTime', () {
    test('formats the UTC date and 24h time', () {
      expect(
        fmtDateTime(DateTime.utc(2026, 11, 20, 8, 5)),
        'Nov 20, 2026 · 08:05',
      );
      expect(
        fmtDateTime(DateTime.utc(2026, 1, 2, 20, 5)),
        'Jan 2, 2026 · 20:05',
      );
    });

    test('oneTimeInstantUtc reads a dated one-time alarm', () {
      expect(
        oneTimeInstantUtc(
          _alarm(
            repeat: AlarmRepeat.oneTime,
            year: 2099,
            month: 1,
            day: 2,
            hour: 8,
            minute: 5,
          ),
        ),
        DateTime.utc(2099, 1, 2, 8, 5),
      );
    });
  });

  group('nextOccurrence (UTC only)', () {
    test('daily later today stays today', () {
      final from = DateTime.utc(2026, 9, 17, 7, 0);
      final at = nextOccurrence(_alarm(hour: 8), fromUtc: from)!;
      expect(at.day, 17);
      expect(at.hour, 8);
    });

    test('daily past time rolls to tomorrow', () {
      final from = DateTime.utc(2026, 9, 17, 9, 0);
      final at = nextOccurrence(_alarm(hour: 8), fromUtc: from)!;
      expect(at.day, 18);
    });

    test('weekdays skips weekend', () {
      // Saturday 2026-09-19 10:00 UTC.
      final from = DateTime.utc(2026, 9, 19, 10, 0);
      final at = nextOccurrence(
        _alarm(hour: 8, repeat: AlarmRepeat.weekdays),
        fromUtc: from,
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
        fromUtc: from,
      )!;
      expect(at.weekday, DateTime.sunday);
      expect(at.day, 20);
    });

    test('dated one-time future fires, past returns null', () {
      final future = nextOccurrence(
        _alarm(
            repeat: AlarmRepeat.oneTime, year: 2026, month: 9, day: 20),
        fromUtc: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(future, isNotNull);
      final past = nextOccurrence(
        _alarm(
            repeat: AlarmRepeat.oneTime, year: 2026, month: 9, day: 15),
        fromUtc: DateTime.utc(2026, 9, 17, 7, 0),
      );
      expect(past, isNull);
    });

    test('undated one-time behaves as the next daily UTC slot', () {
      final at = nextOccurrence(
        _alarm(repeat: AlarmRepeat.oneTime, hour: 8),
        fromUtc: DateTime.utc(2026, 9, 17, 9, 0),
      )!;
      expect(at, tz.TZDateTime.utc(2026, 9, 18, 8, 0));
    });

    test('device time zone never shifts a UTC fire instant', () {
      // America/New_York springs forward 2026-03-08. A UTC alarm keeps its
      // absolute instant even though the host wall clock loses an hour.
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      addTearDown(() => tz.setLocalLocation(tz.UTC));
      final at = nextOccurrence(
        _alarm(hour: 12),
        fromUtc: DateTime.utc(2026, 3, 7, 7, 0),
      )!;
      expect(at.toUtc(), DateTime.utc(2026, 3, 7, 12, 0));
      final nextDay = nextOccurrence(
        _alarm(hour: 12),
        fromUtc: DateTime.utc(2026, 3, 8, 13, 0),
      )!;
      expect(nextDay.toUtc(), DateTime.utc(2026, 3, 9, 12, 0));
    });

    test('legacy isUtc flag is ignored', () {
      final from = DateTime.utc(2026, 9, 17, 7, 0);
      final legacyLocal = nextOccurrence(
        _alarm(hour: 8, isUtc: false),
        fromUtc: from,
      );
      final utc = nextOccurrence(
        _alarm(hour: 8, isUtc: true),
        fromUtc: from,
      );
      expect(legacyLocal, utc);
      expect(legacyLocal!.toUtc(), DateTime.utc(2026, 9, 17, 8, 0));
    });
  });
}
