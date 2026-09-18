import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:larm/src/app.dart';
import 'package:larm/src/core/nav.dart';
import 'package:larm/src/core/notifications/background_handler.dart';
import 'package:larm/src/core/notifications/scheduler.dart';
import 'package:larm/src/data/models/alarm.dart';
import 'package:larm/src/data/models/larm_timer.dart';
import 'package:larm/src/data/models/settings.dart';
import 'package:larm/src/data/repos/alarm_repo.dart';
import 'package:larm/src/data/repos/settings_repo.dart';
import 'package:larm/src/data/repos/timer_repo.dart';
import 'package:larm/src/features/trigger/trigger_page.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'widget_test.dart' show testAlarm, testTimer;

class FakeBackend implements AlarmBackend {
  final scheduled = <ScheduledFire>[];
  final cancelled = <int>[];

  @override
  Future<void> schedule(ScheduledFire fire) async {
    scheduled.add(fire);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}

Future<ProviderScope> triggerScope({
  required Directory dir,
  required String suffix,
  required FakeBackend backend,
  required Widget child,
  List<Alarm> alarms = const [],
  List<LarmTimer> timers = const [],
}) async {
  // Widget tests bypass main(): timezone DB must be set up (safe to repeat).
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
      schedulerProvider.overrideWithValue(
        AlarmScheduler(backend: backend),
      ),
    ],
    // Pushed on top of a stub home: popping the root route throws, and the
    // real app always pushes /trigger over the dashboard.
    child: MaterialApp(home: _Launcher(trigger: child)),
  );
}

/// Pushes [trigger] over a stub home on the first frame.
class _Launcher extends StatefulWidget {
  const _Launcher({required this.trigger});

  final Widget trigger;

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  bool _pushed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pushed) return;
    _pushed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => widget.trigger),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('underneath'));
  }
}

Future<void> spin(WidgetTester tester, [int frames = 6]) async {
  // Pump WITH durations: route transitions and entrance animations run on
  // the fake clock, which bare pump() never advances inside runAsync.
  for (var i = 0; i < frames; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls [finder] into view on the trigger page (single scrollable) and
/// taps it. Needed since the expressive layout can overflow short screens.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 100);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder);
}

Alarm _dailyAlarm(String id) => testAlarm(id: id);

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('larm_trigger');
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

  testWidgets('repeating alarm stop reschedules and pops',
      (WidgetTester tester) async {
    final backend = FakeBackend();
    late ProviderContainer container;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await triggerScope(
          dir: dir,
          suffix: 'stop',
          backend: backend,
          alarms: [_dailyAlarm('ring')],
          child: const TriggerPage(alarmId: 'ring'),
        ),
      );
      await tester.pump();
      await spin(tester, 4);
      container = ProviderScope.containerOf(
          tester.element(find.text('Morning ring')));

      await tapVisible(tester, find.text('Stop'));
      await spin(tester);
    });

    // Still enabled with a fresh schedule for the next occurrence.
    expect(
        container.read(alarmRepositoryProvider).getById('ring')?.enabled,
        isTrue);
    expect(
      backend.scheduled
          .where((f) =>
              f.id == AlarmScheduler.notificationIdForAlarm('ring'))
          .length,
      1,
    );
    expect(find.text('Morning ring'), findsNothing);
  });

  testWidgets('one-time alarm stop disables it', (WidgetTester tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      final alarm = testAlarm(id: 'once')
        ..repeat = AlarmRepeat.oneTime
        ..year = 2026
        ..month = 9
        ..day = 20;
      await tester.pumpWidget(
        await triggerScope(
          dir: dir,
          suffix: 'once',
          backend: FakeBackend(),
          alarms: [alarm],
          child: const TriggerPage(alarmId: 'once'),
        ),
      );
      await tester.pump();
      await spin(tester, 4);
      container = ProviderScope.containerOf(
          tester.element(find.text('Morning once')));

      await tapVisible(tester, find.text('Stop'));
      await spin(tester);
    });

    expect(
        container.read(alarmRepositoryProvider).getById('once')?.enabled,
        isFalse);
  });

  testWidgets('snooze reschedules in the same slot', (WidgetTester tester) async {
    final backend = FakeBackend();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await triggerScope(
          dir: dir,
          suffix: 'snooze',
          backend: backend,
          alarms: [_dailyAlarm('nap')],
          child: const TriggerPage(alarmId: 'nap', snoozeRemaining: 2),
        ),
      );
      await tester.pump();
      await spin(tester, 4);
      expect(find.text('2 snoozes left'), findsOneWidget);

      await tapVisible(tester, find.textContaining('Snooze'));
      await spin(tester);
    });

    final fires = backend.scheduled
        .where((f) => f.id == AlarmScheduler.notificationIdForAlarm('nap'))
        .toList();
    expect(fires, hasLength(1));
    final delta =
        fires.single.when.toUtc().difference(DateTime.now().toUtc());
    expect(delta.inMinutes, inInclusiveRange(3, 6));
    expect(find.text('Morning nap'), findsNothing);
  });

  testWidgets('snooze disabled when none left', (WidgetTester tester) async {
    final backend = FakeBackend();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await triggerScope(
          dir: dir,
          suffix: 'nosnooze',
          backend: backend,
          alarms: [_dailyAlarm('last')],
          child: const TriggerPage(alarmId: 'last', snoozeRemaining: 0),
        ),
      );
      await tester.pump();
      await spin(tester, 4);
      expect(find.text('No snoozes left'), findsOneWidget);

      await tester.tap(find.textContaining('Snooze'), warnIfMissed: false);
      await spin(tester, 3);
    });

    expect(backend.scheduled, isEmpty);
    expect(find.text('Morning last'), findsOneWidget);
  });

  testWidgets('timer completion stop marks it done', (WidgetTester tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      final timer = testTimer(id: 'done')
        ..status = TimerStatus.running
        ..targetUtc = DateTime.now().toUtc().add(const Duration(seconds: 1));
      await tester.pumpWidget(
        await triggerScope(
          dir: dir,
          suffix: 'timer',
          backend: FakeBackend(),
          timers: [timer],
          child: const TriggerPage(timerId: 'done'),
        ),
      );
      await tester.pump();
      await spin(tester, 4);
      container = ProviderScope.containerOf(tester.element(find.text('Pasta')));
      expect(find.text('Done'), findsOneWidget);

      await tapVisible(tester, find.text('Stop'));
      await spin(tester);
    });

    expect(
        container.read(timerRepositoryProvider).getById('done')?.status,
        TimerStatus.done);
  });

  testWidgets('missing entry shows Gone with Close', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await triggerScope(
          dir: dir,
          suffix: 'gone',
          backend: FakeBackend(),
          child: const TriggerPage(alarmId: 'missing'),
        ),
      );
      await tester.pump();
      await spin(tester, 4);
      expect(find.text('Gone'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await spin(tester);
      expect(find.text('Gone'), findsNothing);
    });
  });

  testWidgets('autoAction stop executes without tapping',
      (WidgetTester tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await triggerScope(
          dir: dir,
          suffix: 'auto',
          backend: FakeBackend(),
          alarms: [_dailyAlarm('auto')],
          child: const TriggerPage(alarmId: 'auto', autoAction: 'stop'),
        ),
      );
      await tester.pump();
      await tester.pump();
      // Anchor on the stub home: the auto-action may pop the trigger page
      // before we look at it.
      container = ProviderScope.containerOf(
          tester.element(find.text('underneath')));
      await spin(tester);
    });

    expect(
        container.read(alarmRepositoryProvider).getById('auto')?.enabled,
        isTrue);
    expect(find.text('Morning auto'), findsNothing);
  });

  testWidgets('trigger opens via /trigger route arguments',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await triggerScope(
          dir: dir,
          suffix: 'route',
          backend: FakeBackend(),
          alarms: [_dailyAlarm('routed')],
          child: const LarmApp(),
        ),
      );
      await tester.pump();
    });

    // Navigation animations use the fake clock: push outside runAsync.
    larmNavigatorKey.currentState?.pushNamed(
      '/trigger',
      arguments: const {'alarmId': 'routed'},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Morning routed'), findsOneWidget);
  });

  group('parseFirePayload', () {
    test('parses alarm/timer payloads, rejects junk', () {
      expect(parseFirePayload('alarm:abc'), (kind: 'alarm', id: 'abc'));
      expect(parseFirePayload('timer:abc'), (kind: 'timer', id: 'abc'));
      expect(parseFirePayload(null), isNull);
      expect(parseFirePayload('tap'), isNull);
      expect(parseFirePayload('alarm:'), isNull);
      expect(parseFirePayload('push:abc'), isNull);
    });
  });
}
