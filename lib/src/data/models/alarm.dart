import 'package:hive_ce/hive.dart';

part 'alarm.g.dart';

/// Repeat encoding stored in [Alarm.repeat].
/// 0 one-time, 1 daily, 2 weekdays (Mon–Fri), 3 custom [Alarm.days].
///
/// Named [AlarmRepeat] to avoid clashing with Flutter's [RepeatMode].
abstract final class AlarmRepeat {
  static const int oneTime = 0;
  static const int daily = 1;
  static const int weekdays = 2;
  static const int custom = 3;
}

/// Stored alarm. Time fields are wall-clock in the zone implied by [isUtc]:
/// local device zone when false, UTC when true.
@HiveType(typeId: 0)
class Alarm extends HiveObject {
  Alarm({
    required this.id,
    required this.title,
    required this.isUtc,
    required this.hour,
    required this.minute,
    this.year,
    this.month,
    this.day,
    required this.repeat,
    required this.days,
    required this.enabled,
    required this.soundId,
    required this.vibId,
    required this.createdAtUtc,
  });

  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  bool isUtc;

  @HiveField(3)
  int hour;

  @HiveField(4)
  int minute;

  /// Dated one-time alarms only; null otherwise.
  @HiveField(5)
  int? year;

  @HiveField(6)
  int? month;

  @HiveField(7)
  int? day;

  @HiveField(8)
  int repeat;

  /// Length 7, Monday = index 0. Only meaningful for [RepeatMode.custom].
  @HiveField(9)
  List<bool> days;

  @HiveField(10)
  bool enabled;

  @HiveField(11)
  String soundId;

  @HiveField(12)
  String vibId;

  @HiveField(13)
  DateTime createdAtUtc;
}
