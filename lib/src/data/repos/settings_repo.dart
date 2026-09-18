import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../models/settings.dart';

const String _settingsKey = 'app';

final settingsBoxProvider = Provider<Box<Settings>>(
    (_) => throw UnimplementedError('Set in main()'));

/// In-memory default so widgets/tests work without Hive; main() overrides
/// with the box-backed controller.
final settingsControllerProvider =
    StateNotifierProvider<SettingsController, Settings>(
        (_) => SettingsController(null, Settings.defaults()));

/// App settings store. Single Hive record under `'app'`.
class SettingsController extends StateNotifier<Settings> {
  SettingsController(this._box, super.initial);

  final Box<Settings>? _box;

  Future<void> _persist(Settings next) async {
    state = next;
    final box = _box;
    if (box != null) await box.put(_settingsKey, next);
  }

  Future<void> updateSoundMode(int v) =>
      _persist(state.copyWith(soundMode: v));
  Future<void> updateSnooze(int min, int count) =>
      _persist(state.copyWith(snoozeMin: min, snoozeCount: count));
  Future<void> updateTheme({required int mode, required int family}) =>
      _persist(state.copyWith(themeMode: mode, family: family));
  Future<void> updateTimeFormat(int v) =>
      _persist(state.copyWith(timeFormat: v));
  Future<void> updateDefaultSound(String id) =>
      _persist(state.copyWith(defaultSoundId: id));
}

Settings loadSettings(Box<Settings> box) =>
    box.get(_settingsKey) ?? Settings.defaults();
