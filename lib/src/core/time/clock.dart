import 'package:timezone/timezone.dart' as tz;

import '../../data/models/alarm.dart';

/// Absolute UTC now. Larm is UTC-only: no device-local wall time is used
/// anywhere in scheduling, display, or repeat calculations.
DateTime utcNow() => DateTime.now().toUtc();

/// Formats the UTC fields of [dt] in 24-hour time. Larm never shows 12-hour
/// time: the device locale and the legacy `timeFormat` setting are ignored.
String fmtTime(DateTime dt) {
  final minutes = dt.minute.toString().padLeft(2, '0');
  return '${dt.hour.toString().padLeft(2, '0')}:$minutes';
}

/// Convenience for callers holding a local [DateTime]: format its UTC view.
String fmtUtcTime(DateTime dt) => fmtTime(dt.toUtc());

const List<String> _shortMonths = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats the UTC date and time fields of [dt] in 24-hour time.
///
/// Example: `Nov 20, 2026 · 08:05`.
String fmtDateTime(DateTime dt) {
  final utc = dt.toUtc();
  return '${_shortMonths[utc.month - 1]} ${utc.day}, ${utc.year} · '
      '${fmtTime(utc)}';
}

/// The UTC instant a dated one-time alarm is configured for, or null when
/// the alarm repeats or has no explicit date.
DateTime? oneTimeInstantUtc(Alarm alarm) {
  if (alarm.repeat != AlarmRepeat.oneTime) return null;
  final year = alarm.year;
  final month = alarm.month;
  final day = alarm.day;
  if (year == null || month == null || day == null) return null;
  return DateTime.utc(year, month, day, alarm.hour, alarm.minute);
}

/// Next UTC fire instant strictly after [fromUtc], or null when a dated
/// one-time alarm has already passed.
///
/// All repeats — daily, weekdays, custom and one-time — are evaluated in
/// UTC. The device time zone never affects when an alarm fires or what the
/// dashboard displays.
tz.TZDateTime? nextOccurrence(Alarm alarm, {required DateTime fromUtc}) {
  final base = fromUtc.toUtc();

  tz.TZDateTime candidate(int year, int month, int day) =>
      tz.TZDateTime.utc(year, month, day, alarm.hour, alarm.minute);

  bool isAfter(tz.TZDateTime c) => c.isAfter(base);

  tz.TZDateTime nextDay(int offset) =>
      tz.TZDateTime.from(base, tz.UTC).add(Duration(days: offset));

  switch (alarm.repeat) {
    case AlarmRepeat.oneTime:
      if (alarm.year != null && alarm.month != null && alarm.day != null) {
        final at = candidate(alarm.year!, alarm.month!, alarm.day!);
        return isAfter(at) ? at : null;
      }
      // Undated one-time behaves like the next daily UTC slot.
      final today = candidate(base.year, base.month, base.day);
      if (isAfter(today)) return today;
      final tomorrow = nextDay(1);
      return candidate(tomorrow.year, tomorrow.month, tomorrow.day);

    case AlarmRepeat.daily:
      final today = candidate(base.year, base.month, base.day);
      if (isAfter(today)) return today;
      final tomorrow = nextDay(1);
      return candidate(tomorrow.year, tomorrow.month, tomorrow.day);

    case AlarmRepeat.weekdays:
    case AlarmRepeat.custom:
      final useCustom = alarm.repeat == AlarmRepeat.custom;
      for (var offset = 0; offset < 8; offset++) {
        final day = nextDay(offset);
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
