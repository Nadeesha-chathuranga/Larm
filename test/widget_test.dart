import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:larm/src/app.dart';
import 'package:larm/src/data/models/alarm.dart';
import 'package:larm/src/data/models/larm_timer.dart';
import 'package:larm/src/data/models/settings.dart';
import 'package:larm/src/data/repos/alarm_repo.dart';
import 'package:larm/src/data/repos/settings_repo.dart';
import 'package:larm/src/data/repos/timer_repo.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Builds a Hive-backed [ProviderScope] for dashboard widget tests.
///
/// IMPORTANT: Hive performs real async file IO, which hangs in a
/// `testWidgets` fake-async zone. Call this (and all pumps/interactions)
/// inside `tester.runAsync`. The analog clock ticks forever, so use
/// [WidgetTester.pump], never [WidgetTester.pumpAndSettle].
Future<ProviderScope> dashboardScope({
  List<Alarm> alarms = const [],
  List<LarmTimer> timers = const [],
  required Directory dir,
  required String suffix,
}) async {
  // Widget tests bypass main(), so the timezone DB must be set up here
  // (safe to repeat across tests in the isolate).
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.UTC);

  Hive.init(dir.path);
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(AlarmAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(LarmTimerAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SettingsAdapter());

  final alarmBox = await Hive.openBox<Alarm>('alarms_$suffix');
  final timerBox = await Hive.openBox<LarmTimer>('timers_$suffix');
  final settingsBox = await Hive.openBox<Settings>('settings_$suffix');
  await alarmBox.clear();
  await timerBox.clear();
  await settingsBox.clear();

  final settings = Settings.defaults();
  await settingsBox.put('app', settings);
  for (final alarm in alarms) {
    await alarmBox.put(alarm.id, alarm);
  }
  for (final timer in timers) {
    await timerBox.put(timer.id, timer);
  }

  return ProviderScope(
    overrides: [
      alarmBoxProvider.overrideWithValue(alarmBox),
      timerBoxProvider.overrideWithValue(timerBox),
      settingsBoxProvider.overrideWithValue(settingsBox),
      settingsControllerProvider.overrideWith(
        (ref) => SettingsController(settingsBox, settings),
      ),
    ],
    child: const LarmApp(),
  );
}

Alarm testAlarm({String id = 'a1', bool enabled = true}) => Alarm(
      id: id,
      title: 'Morning $id',
      isUtc: false,
      hour: 8,
      minute: 0,
      repeat: AlarmRepeat.daily,
      days: List<bool>.filled(7, false),
      enabled: enabled,
      soundId: 'glass_chime',
      vibId: 'short',
      createdAtUtc: DateTime.utc(2026, 1, 1),
    );

LarmTimer testTimer({String id = 't1'}) => LarmTimer(
      id: id,
      title: 'Pasta',
      durationSec: 600,
      remainingSec: 600,
      status: TimerStatus.idle,
      enabled: true,
    );

void main() {
  testWidgets('App boots to Larm dashboard', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('larm_widget');
      addTearDown(() async {
        try {
          await Hive.close().timeout(const Duration(seconds: 10));
        } catch (_) {
          // Best effort only (see dashboard_test teardown note).
        }
        try {
          await dir.delete(recursive: true).timeout(
                const Duration(seconds: 10),
              );
        } catch (_) {
          // Best effort only.
        }
      });
      await tester.pumpWidget(
        await dashboardScope(dir: dir, suffix: 'boot'),
      );
      await tester.pump();

      expect(find.text('Larm'), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
