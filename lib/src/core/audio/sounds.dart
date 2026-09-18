/// Bundled-tone catalog. Audio files live in `assets/sounds/` (in-app
/// preview) and `android/.../res/raw/` (notification channels). Ids are
/// stable: alarms saved today keep working as tones ship.
class AlarmSound {
  const AlarmSound(this.id, this.label, this.category);

  final String id;
  final String label;

  /// One of `General`, `Classic`, `Melodic`, `Ambient`.
  final String category;
}

const List<String> soundCategories = [
  'General',
  'Classic',
  'Melodic',
  'Ambient',
];

const List<AlarmSound> alarmSounds = [
  AlarmSound('system', 'System default', 'General'),
  AlarmSound('mono_beep', 'Mono Beep', 'Classic'),
  AlarmSound('digital_beacon', 'Digital Beacon', 'Classic'),
  AlarmSound('electric_alarm', 'Electric Alarm', 'Classic'),
  AlarmSound('sunrise_glow', 'Sunrise Glow', 'Classic'),
  AlarmSound('glass_chime', 'Glass Chime', 'Melodic'),
  AlarmSound('morning_dew', 'Morning Dew', 'Melodic'),
  AlarmSound('night_owl', 'Night Owl', 'Melodic'),
  AlarmSound('soft_wake', 'Soft Wake', 'Ambient'),
  AlarmSound('radar_pulse', 'Radar Pulse', 'Ambient'),
  AlarmSound('pulse_ring', 'Pulse Ring', 'Ambient'),
  AlarmSound('zen_bowl', 'Zen Bowl', 'Ambient'),
  AlarmSound('ocean_wake', 'Ocean Wake', 'Ambient'),
];

/// Vibration pattern catalog. `pattern` alternates wait/vibrate millis;
/// empty [pattern] with a [duration] means a single buzz.
class VibrationPattern {
  const VibrationPattern(this.id, this.label, this.duration, this.pattern);

  final String id;
  final String label;
  final int duration;
  final List<int> pattern;
}

const List<VibrationPattern> vibrationPatterns = [
  VibrationPattern('off', 'Off', 0, []),
  VibrationPattern('short', 'Short', 120, []),
  VibrationPattern('long', 'Long', 600, []),
  VibrationPattern('double', 'Double', 0, [0, 150, 120, 300]),
];

VibrationPattern vibrationById(String id) => vibrationPatterns.firstWhere(
      (p) => p.id == id,
      orElse: () => vibrationPatterns[1],
    );

bool isKnownSound(String id) => alarmSounds.any((s) => s.id == id);

/// Display label for a sound id (falls back to the raw id).
String soundLabel(String id) {
  for (final s in alarmSounds) {
    if (s.id == id) return s.label;
  }
  return id;
}

/// Category for a sound id (empty when unknown).
String soundCategory(String id) {
  for (final s in alarmSounds) {
    if (s.id == id) return s.category;
  }
  return '';
}
