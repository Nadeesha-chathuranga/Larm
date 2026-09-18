/// Curated theme families. Mono (pure B&W) is the default and honors the
/// README identity; the rest are minimalist accents on the same layout.
enum LarmThemeFamily {
  mono,
  midnight,
  arctic,
  forest,
  ember,
  ocean,
}

extension LarmThemeFamilyX on LarmThemeFamily {
  String get displayName {
    switch (this) {
      case LarmThemeFamily.mono:
        return 'Mono';
      case LarmThemeFamily.midnight:
        return 'Midnight OLED';
      case LarmThemeFamily.arctic:
        return 'Arctic Mist';
      case LarmThemeFamily.forest:
        return 'Forest Night';
      case LarmThemeFamily.ember:
        return 'Ember Dusk';
      case LarmThemeFamily.ocean:
        return 'Ocean Tide';
    }
  }
}

/// Stored as [Settings.family]; keep order stable (0 = mono default).
LarmThemeFamily familyFromIndex(int index) {
  final values = LarmThemeFamily.values;
  if (index < 0 || index >= values.length) return LarmThemeFamily.mono;
  return values[index];
}
