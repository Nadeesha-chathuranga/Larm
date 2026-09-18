import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'src/app.dart';
import 'src/core/notifications/scheduler.dart';
import 'src/core/notifications/service.dart';
import 'src/data/models/alarm.dart';
import 'src/data/models/larm_timer.dart';
import 'src/data/models/settings.dart';
import 'src/data/repos/alarm_repo.dart';
import 'src/data/repos/settings_repo.dart';
import 'src/data/repos/timer_repo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tzdata.initializeTimeZones();
  try {
    final name = (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(name));
  } catch (_) {
    tz.setLocalLocation(tz.UTC);
  }

  await Hive.initFlutter();
  Hive
    ..registerAdapter(AlarmAdapter())
    ..registerAdapter(LarmTimerAdapter())
    ..registerAdapter(SettingsAdapter());

  final alarmBox = await Hive.openBox<Alarm>('alarms');
  final timerBox = await Hive.openBox<LarmTimer>('timers');
  final settingsBox = await Hive.openBox<Settings>('settings');
  final initialSettings = loadSettings(settingsBox);

  await NotificationService.init();

  // M2: recompute every slot on cold start. Covers reboot (plugin restores
  // its own schedules too), app update, and permission-revocation recovery.
  // Never crash boot for a scheduling failure.
  try {
    await AlarmScheduler(backend: PluginBackend()).syncAll(
      alarms: alarmBox.values.toList(),
      timers: timerBox.values.toList(),
      settings: initialSettings,
      now: DateTime.now(),
    );
  } catch (_) {
    // Scheduling is best-effort until permissions are granted (M3 explains).
  }

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
      child: const LarmApp(),
    ),
  );
}
