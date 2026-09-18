import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:larm/src/data/models/larm_timer.dart';
import 'package:larm/src/data/repos/alarm_repo.dart';
import 'package:larm/src/data/repos/timer_repo.dart';
import 'widget_test.dart' show dashboardScope, testAlarm;

/// Pumps [frames] real-time frames so container-transform and route
/// animations progress inside `runAsync`. Pumps carry fake durations too:
/// OpenContainer push/pop transitions run on the fake clock, which bare
/// pump() never advances. See dashboard_test for why Hive needs runAsync.
Future<void> spin(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until the editor route finishes popping (its TextField leaves
/// the tree), up to ~2s. Prevents matching editor text against the
/// dashboard tile underneath mid-transition.
Future<void> pumpUntilPopped(WidgetTester tester) async {
  for (var i = 0;
      i < 20 && find.byType(TextField).evaluate().isNotEmpty;
      i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}
/// Scrolls [finder] into view (long forms lazily build off-screen rows)
/// and taps it. Drags from the far left edge so the centered wheel pickers
/// never hijack the gesture; fake-zone pumps settle the scroll. Loops until
/// the center is hittable, not merely built.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 15; i++) {
    final matches = finder.evaluate();
    if (matches.isNotEmpty) {
      final dy = tester.getCenter(finder).dy;
      if (dy > 20 && dy < 580) break;
      final dir = dy >= 580 ? -350.0 : 350.0;
      await tester.dragFrom(const Offset(30, 500), Offset(0, dir));
    } else {
      await tester.dragFrom(const Offset(30, 500), const Offset(0, -350));
    }
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('larm_editor');
  });

  tearDownAll(() async {
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

  testWidgets('creates an alarm with defaults + title',
      (WidgetTester tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(dir: dir, suffix: 'create'),
      );
      await tester.pump();
      container =
          ProviderScope.containerOf(tester.element(find.text('Larm')));

      await tester.tap(find.byTooltip('New alarm or timer'));
      await spin(tester);
      expect(find.text('New alarm'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Gym');
      await tapVisible(tester, find.text('Save alarm'));
      await spin(tester);
      await pumpUntilPopped(tester);
    });

    final alarms = container.read(alarmRepositoryProvider).all();
    expect(alarms, hasLength(1));
    expect(alarms.single.title, 'Gym');
    expect(alarms.single.enabled, isTrue);
    expect(find.text('Gym'), findsOneWidget);
  });

  testWidgets('creates and starts a timer', (WidgetTester tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(dir: dir, suffix: 'timer'),
      );
      await tester.pump();
      container =
          ProviderScope.containerOf(tester.element(find.text('Larm')));

      await tester.tap(find.byTooltip('New alarm or timer'));
      await spin(tester);
      await tester.tap(find.text('Timer'));
      await spin(tester, 4);
      expect(find.text('New timer'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Pasta');
      await tester.tap(find.text('Start timer'));
      await spin(tester);
      await pumpUntilPopped(tester);
    });

    final timers = container.read(timerRepositoryProvider).all();
    expect(timers, hasLength(1));
    expect(timers.single.title, 'Pasta');
    expect(timers.single.status, TimerStatus.running);
    expect(timers.single.durationSec, 300);
    expect(find.text('Pasta'), findsOneWidget);
  });

  testWidgets('edits an existing alarm with prefilled title',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(
          dir: dir,
          suffix: 'edit',
          alarms: [testAlarm(id: 'e1')],
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Morning e1'));
      await spin(tester);
      expect(find.text('Edit alarm'), findsOneWidget);
      expect(find.text('Morning e1'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'Gym updated');
      await tapVisible(tester, find.text('Save alarm'));
      await spin(tester);
      await pumpUntilPopped(tester);
      expect(find.text('Gym updated'), findsOneWidget);
    });
  });

  testWidgets('UTC toggle shows conversion preview',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(dir: dir, suffix: 'utc'),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('New alarm or timer'));
      await spin(tester);
      expect(find.textContaining('Local'), findsWidgets);

      await tester.tap(find.text('UTC'));
      await spin(tester, 4);
      expect(find.textContaining('UTC'), findsWidgets);
    });
  });

  testWidgets('custom repeat requires a day', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(dir: dir, suffix: 'custom'),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('New alarm or timer'));
      await spin(tester);
      await tapVisible(tester, find.text('Custom'));
      await spin(tester, 4);
      await tapVisible(tester, find.text('Save alarm'));
      await spin(tester, 4);

      // Still on the editor: validation blocked the save.
      expect(find.text('New alarm'), findsOneWidget);
      expect(find.text('Pick at least one day'), findsOneWidget);
    });
  });
}
