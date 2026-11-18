import 'package:flutter_test/flutter_test.dart';
import 'package:larm/src/core/migration.dart';
import 'package:larm/src/data/models/alarm.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Alarm _alarm({required int repeat, int hour = 8, List<bool>? days}) {
  return Alarm(
    id: 'm',
    title: 'Migrate',
    isUtc: true,
    hour: hour,
    minute: 30,
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

  test('daily repeat becomes a one-time alarm at its next UTC slot', () {
    final alarm = _alarm(repeat: AlarmRepeat.daily, hour: 8);
    final now = DateTime.utc(2026, 11, 18, 9);

    final hasFuture = convertRepeatingAlarmToOneTime(alarm, nowUtc: now);

    expect(hasFuture, isTrue);
    expect(alarm.repeat, AlarmRepeat.oneTime);
    expect(alarm.year, 2026);
    expect(alarm.month, 11);
    expect(alarm.day, 19);
    expect(alarm.hour, 8);
    expect(alarm.minute, 30);
    expect(alarm.days.every((d) => !d), isTrue);
  });

  test('custom repeat uses the next matching UTC day', () {
    final alarm = _alarm(
      repeat: AlarmRepeat.custom,
      hour: 6,
      days: [false, false, false, false, false, true, false], // Saturday
    );
    final now = DateTime.utc(2026, 11, 18, 12); // Wednesday

    final hasFuture = convertRepeatingAlarmToOneTime(alarm, nowUtc: now);

    expect(hasFuture, isTrue);
    expect(alarm.repeat, AlarmRepeat.oneTime);
    expect(DateTime.utc(alarm.year!, alarm.month!, alarm.day!).weekday, 6);
    expect(alarm.hour, 6);
    expect(alarm.minute, 30);
  });

  test('one-time alarms are left unchanged', () {
    final alarm = _alarm(repeat: AlarmRepeat.oneTime)
      ..year = 2026
      ..month = 11
      ..day = 20;

    final hasFuture = convertRepeatingAlarmToOneTime(
      alarm,
      nowUtc: DateTime.utc(2026, 11, 18),
    );

    expect(hasFuture, isTrue);
    expect(alarm.year, 2026);
    expect(alarm.month, 11);
    expect(alarm.day, 20);
    expect(alarm.hour, 8);
  });

  test('expired repeating alarms report no future slot', () {
    final alarm = _alarm(repeat: AlarmRepeat.custom)
      ..days = List<bool>.filled(7, false);

    final hasFuture = convertRepeatingAlarmToOneTime(
      alarm,
      nowUtc: DateTime.utc(2026, 11, 18),
    );

    expect(hasFuture, isFalse);
    expect(alarm.repeat, AlarmRepeat.custom);
  });
}
