import '../data/models/alarm.dart';
import 'time/clock.dart';

/// Converts a legacy repeating alarm into a one-time alarm at its next UTC
/// slot. Returns false when there is no future slot; the caller should then
/// disable the alarm instead of letting it fire in the past.
///
/// Stored repeat fields are cleared but kept in the Hive schema for stability.
bool convertRepeatingAlarmToOneTime(Alarm alarm, {required DateTime nowUtc}) {
  if (alarm.repeat == AlarmRepeat.oneTime) return true;

  final next = nextOccurrence(alarm, fromUtc: nowUtc);
  if (next == null) return false;

  alarm
    ..year = next.year
    ..month = next.month
    ..day = next.day
    ..hour = next.hour
    ..minute = next.minute
    ..repeat = AlarmRepeat.oneTime
    ..days = List<bool>.filled(7, false);
  return true;
}
