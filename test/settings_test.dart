import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:larm/src/core/audio/sounds.dart';
import 'package:larm/src/core/notifications/channels.dart';
import 'package:larm/src/data/repos/settings_repo.dart';

import 'widget_test.dart' show dashboardScope;

Future<void> spin(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

/// Scrolls [finder] into the viewport (long forms lazily build rows) and
/// taps it. Drags from the far left edge to avoid nested scrollables.
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
    dir = await Directory.systemTemp.createTemp('larm_settings');
  });

  tearDownAll(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best effort only (see dashboard_test teardown note).
    }
    try {
      await dir.delete(recursive: true).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best effort only.
    }
  });

  group('channels', () {
    test('channelFor encodes tone and volume in a versioned channel id', () {
      expect(
        channelFor(
          overrideMode: true,
          soundId: 'glass_chime',
          volume: 50,
        ),
        'larm_override_v3_glass_chime_v50',
      );
      expect(
        channelFor(
          overrideMode: false,
          soundId: 'system',
          volume: 35,
        ),
        'larm_follow_v3_glass_chime_v40',
      );
      expect(fireChannelIds(soundId: 'zen_bowl', volume: 70), [
        'larm_follow_v3_zen_bowl_v70',
        'larm_override_v3_zen_bowl_v70',
      ]);
    });

    test('status channels stay silent', () {
      final channels = staticChannels();
      expect(channels, hasLength(2));
      final armed = channels.singleWhere((c) => c.id == larmArmedV2);
      expect(armed.playSound, isFalse);
      expect(armed.enableVibration, isFalse);
      final rang = channels.singleWhere((c) => c.id == larmRangV2);
      expect(rang.playSound, isFalse);
      expect(rang.enableVibration, isFalse);
    });

    test('fire channel sound reflects the volume bucket', () {
      final follow = fireChannel(
        id: channelFor(
          overrideMode: false,
          soundId: 'glass_chime',
          volume: 35,
        ),
        name: 'Alarms',
        soundId: 'glass_chime',
        volume: 35,
        bypassDnd: false,
      );
      expect(follow.playSound, isTrue);
      expect(follow.bypassDnd, isFalse);
      expect(follow.sound, isA<RawResourceAndroidNotificationSound>());
      expect(
        (follow.sound! as RawResourceAndroidNotificationSound).sound,
        'glass_chime_v40',
      );

      final muted = fireChannel(
        id: channelFor(
          overrideMode: false,
          soundId: 'glass_chime',
          volume: 0,
        ),
        name: 'Alarms',
        soundId: 'glass_chime',
        volume: 0,
        bypassDnd: false,
      );
      expect(muted.playSound, isFalse);
      expect(muted.sound, isNull);
    });

    test('override channel bypasses DND and uses the same scaled tone', () {
      final override = fireChannel(
        id: channelFor(
          overrideMode: true,
          soundId: 'zen_bowl',
          volume: 100,
        ),
        name: 'Alarms (override)',
        soundId: 'zen_bowl',
        volume: 100,
        bypassDnd: true,
      );
      expect(override.bypassDnd, isTrue);
      expect(
        (override.sound! as RawResourceAndroidNotificationSound).sound,
        'zen_bowl_v100',
      );
    });

    test('volume buckets round up to 10% steps and system uses default tone',
        () {
      expect(volumeBucket(0), 0);
      expect(volumeBucket(1), 10);
      expect(volumeBucket(10), 10);
      expect(volumeBucket(11), 20);
      expect(volumeBucket(100), 100);
      expect(rawSoundForVolume('system', 35), 'glass_chime_v40');
      expect(rawSoundForVolume('nope', 70), 'glass_chime_v70');
      expect(rawSoundForVolume('glass_chime', 60), 'glass_chime_v60');
    });

    test('legacy v2 and unversioned v3 channel ids are removed on upgrade', () {
      final legacy = legacyChannelIds();
      expect(legacy, contains('larm_follow_v2'));
      expect(legacy, contains('larm_override_v2'));
      expect(legacy, contains('larm_tone_glass_chime_v2'));
      expect(legacy, contains('larm_follow_v3'));
      expect(legacy, contains('larm_override_v3'));
      expect(legacy, hasLength(28));
    });

    test('sound catalog is stable and vibration falls back', () {
      expect(
        alarmSounds.map((s) => s.id),
        containsAll(['glass_chime', 'mono_beep', 'zen_bowl', 'system']),
      );
      expect(isKnownSound('glass_chime'), isTrue);
      expect(isKnownSound('nope'), isFalse);
      expect(vibrationById('double').pattern, isNotEmpty);
      expect(vibrationById('nope').id, 'short');
    });

    test('tone catalog has categories and raw-safe ids', () {
      final ids = alarmSounds.map((s) => s.id).toList();
      // Unique, lowercase, no spaces: valid android res/raw names.
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[a-z0-9_]+$')));
      }
      // Every bundled tone belongs to a known category.
      for (final sound in alarmSounds) {
        expect(soundCategories, contains(sound.category));
      }
      expect(
        alarmSounds.where((s) => s.category == 'Classic').length,
        greaterThanOrEqualTo(4),
      );
      expect(
        alarmSounds.where((s) => s.category == 'Melodic').length,
        greaterThanOrEqualTo(3),
      );
      expect(
        alarmSounds.where((s) => s.category == 'Ambient').length,
        greaterThanOrEqualTo(4),
      );
      // Ten original royalty-free tones in their own first-shown category.
      final popular = alarmSounds
          .where((s) => s.category == 'Popular')
          .toList();
      expect(popular, hasLength(10));
      for (final id in [
        'classic_chime',
        'digital_clock',
        'morning_bell',
        'retro_beep',
        'marimba_wake',
        'radar_sweep',
        'harp_arpeggio',
        'solar_burst',
        'soft_piano',
        'cosmic_pulse',
      ]) {
        expect(popular.map((s) => s.id), contains(id));
        expect(isKnownSound(id), isTrue);
      }
    });
  });

  testWidgets('settings persist across reload', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(dir: dir, suffix: 'persist'),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.text('Larm')),
      );
      final controller = container.read(settingsControllerProvider.notifier);
      await controller.updateSoundMode(1);
      await controller.updateSnooze(10, 2);
      await controller.updateTheme(mode: 2, family: 4);
      await controller.updateTimeFormat(1);
      await controller.updateDefaultSound('zen_bowl');
      await controller.updateDefaultVibration('double');
      await controller.updateAlarmVolume(70);
      await controller.updateRingDuration(45);

      final box = container.read(settingsBoxProvider);
      final reloaded = loadSettings(box);
      expect(reloaded.soundMode, 1);
      expect(reloaded.snoozeMin, 10);
      expect(reloaded.snoozeCount, 2);
      expect(reloaded.themeMode, 2);
      expect(reloaded.family, 4);
      expect(reloaded.timeFormat, 1);
      expect(reloaded.defaultSoundId, 'zen_bowl');
      expect(reloaded.defaultVibId, 'double');
      expect(reloaded.alarmVolume, 70);
      expect(reloaded.volumeFraction, closeTo(0.7, 0.001));
      expect(reloaded.ringDurationSec, 45);
      expect(reloaded.ringDurationMs, 45_000);
    });
  });

  testWidgets('settings page applies snooze, mode and has tone preview', (
    WidgetTester tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      await tester.pumpWidget(await dashboardScope(dir: dir, suffix: 'page'));
      await tester.pump();
      container = ProviderScope.containerOf(tester.element(find.text('Larm')));

      await tester.tap(find.byTooltip('Settings'));
      await spin(tester);
      expect(find.text('Settings'), findsWidgets);

      // Top-to-bottom only: ListView destroys scrolled-past rows, so never
      // navigate back up.
      await tester.tap(find.byTooltip('Increase Minutes'));
      await spin(tester, 4);
      expect(container.read(settingsControllerProvider).snoozeMin, 6);

      await tapVisible(tester, find.text('Always override'));
      await spin(tester, 4);
      expect(container.read(settingsControllerProvider).soundMode, 1);

      expect(find.text('12-hour'), findsNothing);
      expect(find.text('24-hour'), findsNothing);

      await tapVisible(tester, find.text('RINGING DURATION'));
      expect(find.text('10s'), findsWidgets);

      // The tone section now starts with a playable preview and an in-app
      // volume slider. Do not invoke the audio plugin in widget tests.
      await tapVisible(tester, find.text('ALARM TONE'));
      expect(find.byTooltip('Preview Glass Chime'), findsOneWidget);
      expect(find.textContaining('100%'), findsWidgets);
      expect(find.text('System alarm volume'), findsOneWidget);

      await tapVisible(tester, find.text('Double'));
      await spin(tester, 4);
      expect(container.read(settingsControllerProvider).defaultVibId, 'double');
    });
  });

  testWidgets('volume slider stores a real 0-100 value', (
    WidgetTester tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      await tester.pumpWidget(await dashboardScope(dir: dir, suffix: 'volume'));
      await tester.pump();
      container = ProviderScope.containerOf(tester.element(find.text('Larm')));

      await tester.tap(find.byTooltip('Settings'));
      await spin(tester);
      await tapVisible(tester, find.byKey(const Key('alarm-volume-slider')));
      await spin(tester, 4);

      final volume = container.read(settingsControllerProvider).alarmVolume;
      expect(volume, inInclusiveRange(40, 60));
      expect(volume, isNot(1));
    });
  });
}
