import 'package:hive_ce/hive.dart';

part 'settings.g.dart';

/// soundMode: 0 follow system (default), 1 always override.
/// themeMode: 0 system (default), 1 light, 2 dark.
/// timeFormat: retained for Hive schema stability, but ignored — Larm is
/// always 24-hour now.
/// family: index into [LarmThemeFamily] (default 0 = mono).
/// alarmVolume: 0–100 slider. It scales previews, the in-app fallback ring,
/// and the gain-scaled raw tone used by the scheduled Android notification.
/// ringDurationSec: how long a fire rings before the notification/FSI closes.
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
    this.defaultVibId = 'short',
    this.alarmVolume = 100,
    this.ringDurationSec = 10,
  });

  factory Settings.defaults() => Settings(
    soundMode: 0,
    snoozeMin: 5,
    snoozeCount: 3,
    themeMode: 0,
    family: 0,
    timeFormat: 1,
    defaultSoundId: 'glass_chime',
    defaultVibId: 'short',
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

  /// Global vibration pattern id used by every alarm and timer. Legacy
  /// per-alarm `vibId` fields are retained in Hive but ignored by logic.
  @HiveField(7)
  String defaultVibId;

  @HiveField(8)
  int alarmVolume;

  @HiveField(9)
  int ringDurationSec;

  /// Fraction passed to `AudioPlayer.setVolume` for previews and in-app ring.
  double get volumeFraction => (alarmVolume.clamp(0, 100) / 100).toDouble();

  /// Native notification timeout. Clamped to the Settings range.
  int get ringDurationMs => ringDurationSec.clamp(5, 300) * 1000;

  Settings copyWith({
    int? soundMode,
    int? snoozeMin,
    int? snoozeCount,
    int? themeMode,
    int? family,
    int? timeFormat,
    String? defaultSoundId,
    String? defaultVibId,
    int? alarmVolume,
    int? ringDurationSec,
  }) {
    return Settings(
      soundMode: soundMode ?? this.soundMode,
      snoozeMin: snoozeMin ?? this.snoozeMin,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      themeMode: themeMode ?? this.themeMode,
      family: family ?? this.family,
      timeFormat: timeFormat ?? this.timeFormat,
      defaultSoundId: defaultSoundId ?? this.defaultSoundId,
      defaultVibId: defaultVibId ?? this.defaultVibId,
      alarmVolume: alarmVolume ?? this.alarmVolume,
      ringDurationSec: ringDurationSec ?? this.ringDurationSec,
    );
  }
}
