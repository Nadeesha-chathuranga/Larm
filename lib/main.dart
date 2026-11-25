import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'src/app.dart';
import 'src/core/notifications/fire_handoff.dart';
import 'src/core/notifications/scheduler.dart';
import 'src/core/migration.dart';
import 'src/core/prefs.dart';
import 'src/core/notifications/service.dart';
import 'src/data/models/alarm.dart';
import 'src/data/models/larm_timer.dart';
import 'src/data/models/settings.dart';
import 'src/data/repos/alarm_repo.dart';
import 'src/data/repos/settings_repo.dart';
import 'src/data/repos/timer_repo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Larm is UTC-only. Keep the timezone database loaded for the notification
  // plugin, but pin the package's local zone to UTC so no code path can
  // accidentally schedule against the device zone.
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.UTC);

  await Hive.initFlutter();
  Hive
    ..registerAdapter(AlarmAdapter())
    ..registerAdapter(LarmTimerAdapter())
    ..registerAdapter(SettingsAdapter());

  final alarmBox = await Hive.openBox<Alarm>('alarms');
  final timerBox = await Hive.openBox<LarmTimer>('timers');
  final settingsBox = await Hive.openBox<Settings>('settings');
  final initialSettings = loadSettings(settingsBox);

  await _migrateLegacyLocalAlarms(alarmBox);
  await _migrateRepeatsToOneTime(alarmBox);

  await NotificationService.init();

  // Recompute every slot on cold start. Covers reboot (the plugin restores
  // its own schedules too), app update, and permission-revocation recovery.
  // Never crash boot for a scheduling failure.
  try {
    await AlarmScheduler(backend: PluginBackend()).syncAll(
      alarms: alarmBox.values.toList(),
      timers: timerBox.values.toList(),
      settings: initialSettings,
      now: DateTime.now().toUtc(),
    );
  } catch (_) {
    // Scheduling is best-effort until permissions are granted.
  }

  // A fire queued by a locked cold start must be the first visible route so
  // the dashboard never flashes over the alarm popup.
  final initialFire = await FireHandoff.takeInitial();

  runApp(
    ProviderScope(
      overrides: [
        alarmBoxProvider.overrideWithValue(alarmBox),
        timerBoxProvider.overrideWithValue(timerBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        settingsControllerProvider.overrideWith(
          (ref) => SettingsController(settingsBox, initialSettings),
        ),
      ],
      child: LarmApp(initialFire: initialFire),
    ),
  );
}

/// Legacy Local alarms are turned off once on upgrade. They stay stored, but
/// are never scheduled or shown as enabled; the dashboard explains the change.
Future<void> _migrateLegacyLocalAlarms(Box<Alarm> alarmBox) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(utcMigrationKey) == true) return;

  var disabled = 0;
  for (final alarm in alarmBox.values) {
    if (alarm.isUtc || !alarm.enabled) continue;
    alarm.enabled = false;
    await alarm.save();
    disabled++;
  }
  await prefs.setBool(utcMigrationKey, true);
  if (disabled > 0) {
    await prefs.setBool(legacyLocalDisabledKey, true);
  }
}

/// Repeats were removed: every alarm now fires once on a chosen UTC date.
/// Existing repeating alarms keep their next fire time, then become one-time.
Future<void> _migrateRepeatsToOneTime(Box<Alarm> alarmBox) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(oneTimeMigrationKey) == true) return;

  final now = DateTime.now().toUtc();
  for (final alarm in alarmBox.values) {
    final hasFutureSlot = convertRepeatingAlarmToOneTime(alarm, nowUtc: now);
    if (!hasFutureSlot) alarm.enabled = false;
    await alarm.save();
  }
  await prefs.setBool(oneTimeMigrationKey, true);
}
