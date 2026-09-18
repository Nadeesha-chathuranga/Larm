import 'package:hive_ce/hive.dart';

part 'settings.g.dart';

/// soundMode: 0 follow system (default), 1 always override.
/// themeMode: 0 system (default), 1 light, 2 dark.
/// timeFormat: 0 12h (default), 1 24h.
/// family: index into [LarmThemeFamily] (default 0 = mono).
@HiveType(typeId: 2)
class Settings extends HiveObject {
  Settings({
    required this.soundMode,
    required this.snoozeMin,
    required this.snoozeCount,
    required this.themeMode,
    required this.family,
    required this.timeFormat,
    required this.defaultSoundId,
  });

  factory Settings.defaults() => Settings(
        soundMode: 0,
        snoozeMin: 5,
        snoozeCount: 3,
        themeMode: 0,
        family: 0,
        timeFormat: 0,
        defaultSoundId: 'glass_chime',
      );

  @HiveField(0)
  int soundMode;

  @HiveField(1)
  int snoozeMin;

  @HiveField(2)
  int snoozeCount;

  @HiveField(3)
  int themeMode;

  @HiveField(4)
  int family;

  @HiveField(5)
  int timeFormat;

  @HiveField(6)
  String defaultSoundId;

  Settings copyWith({
    int? soundMode,
    int? snoozeMin,
    int? snoozeCount,
    int? themeMode,
    int? family,
    int? timeFormat,
    String? defaultSoundId,
  }) {
    return Settings(
      soundMode: soundMode ?? this.soundMode,
      snoozeMin: snoozeMin ?? this.snoozeMin,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      themeMode: themeMode ?? this.themeMode,
      family: family ?? this.family,
      timeFormat: timeFormat ?? this.timeFormat,
      defaultSoundId: defaultSoundId ?? this.defaultSoundId,
    );
  }
}
