import 'package:timezone/timezone.dart' as tz;

import '../../data/models/alarm.dart';

/// Device-local wall-clock now.
DateTime localNow() => DateTime.now();

/// Absolute UTC now.
DateTime utcNow() => DateTime.now().toUtc();

/// Formats [dt] honoring the 12/24h setting.
String fmtTime(DateTime dt, {required bool use24h}) {
  final minutes = dt.minute.toString().padLeft(2, '0');
  if (use24h) return '${dt.hour.toString().padLeft(2, '0')}:$minutes';
  final suffix = dt.hour < 12 ? 'AM' : 'PM';
  final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  return '$h12:$minutes $suffix';
}

/// Converts an absolute UTC instant into the device zone.
tz.TZDateTime utcToZoned(DateTime utc) =>
    tz.TZDateTime.from(utc.toUtc(), tz.local);

/// Builds a device-zone wall time.
tz.TZDateTime localToZoned(int year, int month, int day, int hour, int minute) =>
    tz.TZDateTime(tz.local, year, month, day, hour, minute);

/// Next fire instant strictly after [fromLocal], or null when a dated
/// one-time alarm already passed.
///
/// Local alarms keep wall time in the device zone (DST-safe via `timezone`);
/// UTC alarms keep the absolute instant regardless of zone.
tz.TZDateTime? nextOccurrence(Alarm alarm, {required DateTime fromLocal}) {
  tz.TZDateTime candidate(int year, int month, int day) {
    if (alarm.isUtc) {
      return tz.TZDateTime.utc(year, month, day, alarm.hour, alarm.minute);
    }
    return tz.TZDateTime(
        tz.local, year, month, day, alarm.hour, alarm.minute);
  }

  bool isAfter(tz.TZDateTime c) => c.isAfter(fromLocal);

  switch (alarm.repeat) {
    case AlarmRepeat.oneTime:
      if (alarm.year != null && alarm.month != null && alarm.day != null) {
        final at = candidate(alarm.year!, alarm.month!, alarm.day!);
        return isAfter(at) ? at : null;
      }
      // Undated one-time behaves like the next daily slot.
      final base = alarm.isUtc ? fromLocal.toUtc() : fromLocal;
      final today = candidate(base.year, base.month, base.day);
      if (isAfter(today)) return today;
      final tomorrow =
          tz.TZDateTime.from(base, alarm.isUtc ? tz.UTC : tz.local)
              .add(const Duration(days: 1));
      return candidate(tomorrow.year, tomorrow.month, tomorrow.day);

    case AlarmRepeat.daily:
      final base = alarm.isUtc ? fromLocal.toUtc() : fromLocal;
      final today = candidate(base.year, base.month, base.day);
      if (isAfter(today)) return today;
      final tomorrow =
          tz.TZDateTime.from(base, alarm.isUtc ? tz.UTC : tz.local)
              .add(const Duration(days: 1));
      return candidate(tomorrow.year, tomorrow.month, tomorrow.day);

    case AlarmRepeat.weekdays:
    case AlarmRepeat.custom:
      final useCustom = alarm.repeat == AlarmRepeat.custom;
      final base = alarm.isUtc ? fromLocal.toUtc() : fromLocal;
      for (var offset = 0; offset < 8; offset++) {
        final day =
            tz.TZDateTime.from(base, alarm.isUtc ? tz.UTC : tz.local)
                .add(Duration(days: offset));
        final weekday = day.weekday; // Mon=1 … Sun=7
        final matches = useCustom
            ? (alarm.days.length == 7 && alarm.days[weekday - 1])
            : weekday <= 5;
        if (!matches) continue;
        final at = candidate(day.year, day.month, day.day);
        if (isAfter(at)) return at;
      }
      return null;
  }
  return null;
}
