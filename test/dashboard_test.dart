import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:larm/src/data/models/alarm.dart';
import 'package:larm/src/data/repos/alarm_repo.dart';
import 'package:larm/src/features/dashboard/widgets/alarm_tile.dart';
import 'widget_test.dart' show dashboardScope, testAlarm, testTimer;

void main() {
  late Directory dir;

  /// Lets real-async work (Hive writes, dismiss/resize animations, async
  /// tap handlers) finish, then redraws. Required because these tests run
  /// inside `tester.runAsync` (Hive hangs in fake async).
  Future<void> settle(WidgetTester tester,
      [int millis = 300]) async {
    await Future<void>.delayed(Duration(milliseconds: millis));
    await tester.pump();
    await tester.pump();
  }

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('larm_dash');
  });

  tearDownAll(() async {
    // Resilient teardown: Hive.close() has been observed to stall after
    // gesture-driven tests on Windows (file-lock release racing the still-
    // mounted box watchers). Never let teardown wedge the runner; temp dirs
    // fall back to OS temp cleanup.
    try {
      await Hive.close().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best effort only.
    }
    try {
      await dir.delete(recursive: true).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best effort only.
    }
  });

  testWidgets('lists alarms with badges and toggles persist',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(
          dir: dir,
          suffix: 'list',
          alarms: [testAlarm(id: 'a1'), testAlarm(id: 'a2')],
        ),
      );
      await tester.pump();

      expect(find.text('Morning a1'), findsOneWidget);
      expect(find.text('Morning a2'), findsOneWidget);
      expect(find.text('LOCAL'), findsNWidgets(2));

      // Toggle the first alarm off; persistence (not exact scheduling) is
      // what this test verifies — platform channels are absent here.
      final switches =
          tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.where((s) => s.value), hasLength(2));
      await tester.tap(find.byType(Switch).first);
      await settle(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.text('Morning a1')),
      );
      expect(container.read(alarmRepositoryProvider).getById('a1')?.enabled,
          isFalse);
    });
  });

  testWidgets('hero swaps local and UTC prominence',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(dir: dir, suffix: 'hero'),
      );
      await tester.pump();

      expect(find.text('Local'), findsOneWidget);
      await tester.tap(find.byType(ActionChip).first);
      await settle(tester);
      expect(find.text('UTC'), findsOneWidget);
    });
  });

  testWidgets('swipe deletes with 5s undo restoring the alarm',
      (WidgetTester tester) async {
    // 1. Real async: Hive setup + first pump (Hive hangs in fake async).
    late ProviderContainer container;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(
          dir: dir,
          suffix: 'delete',
          alarms: [testAlarm(id: 'gone')],
        ),
      );
      await tester.pump();
    });
    container = ProviderScope.containerOf(tester.element(find.text('Larm')));
    expect(find.text('Morning gone'), findsOneWidget);

    // 2. Fake zone: deterministic swipe physics (real timestamps in runAsync
    // confuse the Dismissible release evaluation).
    await tester.drag(find.text('Morning gone'), const Offset(-500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Morning gone'), findsNothing);

    // 3. Real async: let the pending Hive delete land. Then fake-zone
    // pumped durations finish the snackbar entrance (implicit animations
    // only advance on the fake clock, which plain pump() in runAsync
    // never moves).
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        container.read(alarmRepositoryProvider).getById('gone'), isNull);
    expect(find.text('Alarm deleted'), findsOneWidget);

    // 4. Fake zone: tap Undo (upsert pends until real async resumes).
    await tester.tap(find.text('Undo'));

    // 5. Real async: upsert + resync land; tile restored.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        container.read(alarmRepositoryProvider).getById('gone'), isNotNull);
    expect(find.text('Morning gone'), findsOneWidget);
  });

  testWidgets('timers show remaining with working controls',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(
          dir: dir,
          suffix: 'timers',
          timers: [testTimer()],
        ),
      );
      await tester.pump();

      expect(find.text('Pasta'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);

      await tester.tap(find.byTooltip('Start'));
      await settle(tester);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });
  });

  test('repeatLabel covers all modes', () {
    expect(repeatLabel(testAlarm()), 'Daily');
    final weekdays = testAlarm()..repeat = AlarmRepeat.weekdays;
    expect(repeatLabel(weekdays), 'Weekdays');
    final oneTime = testAlarm()..repeat = AlarmRepeat.oneTime;
    expect(repeatLabel(oneTime), 'One-time');
    final custom = testAlarm()
      ..repeat = AlarmRepeat.custom
      ..days = [true, false, false, false, false, false, false];
    expect(repeatLabel(custom), 'Mon');
  });
}
