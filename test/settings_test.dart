import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:larm/src/core/audio/sounds.dart';
import 'package:larm/src/core/notifications/channels.dart';
import 'package:larm/src/core/theme/family.dart';
import 'package:larm/src/core/theme/tokens.dart';
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
      await dir.delete(recursive: true).timeout(
            const Duration(seconds: 10),
          );
    } catch (_) {
      // Best effort only.
    }
  });

  group('channels', () {
    test('channelFor routes override/tone/system correctly', () {
      expect(
        channelFor(overrideMode: true, soundId: 'glass_chime'),
        larmOverrideV2,
      );
      expect(
        channelFor(overrideMode: false, soundId: 'glass_chime'),
        'larm_tone_glass_chime_v2',
      );
      expect(
        channelFor(overrideMode: false, soundId: 'system'),
        larmFollowV2,
      );
      expect(
        channelFor(overrideMode: false, soundId: 'nope'),
        larmFollowV2,
      );
    });

    test('v2 set has follow + 12 tones + override with bypass', () {
      final channels = v2Channels();
      expect(channels, hasLength(14));
      final override =
          channels.singleWhere((c) => c.id == larmOverrideV2);
      expect(override.bypassDnd, isTrue);
      expect(override.importance, isNotNull);
      final tones =
          channels.where((c) => c.id.startsWith('larm_tone_')).toList();
      expect(tones, hasLength(12));
      for (final tone in tones) {
        expect(tone.sound, isNotNull);
      }
    });

    test('sound catalog is stable and vibration falls back', () {
      expect(alarmSounds.map((s) => s.id),
          containsAll(['glass_chime', 'mono_beep', 'zen_bowl', 'system']));
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
    });
  });

  group('themes', () {
    test('all families build light and dark schemes', () {
      for (final family in LarmThemeFamily.values) {
        final light = buildLarmTheme(
            family: family, brightness: Brightness.light);
        final dark = buildLarmTheme(
            family: family, brightness: Brightness.dark);
        expect(light.colorScheme.brightness, Brightness.light);
        expect(dark.colorScheme.brightness, Brightness.dark);
        expect(light.colorScheme.primary,
            isNot(dark.colorScheme.primary));
      }
    });

    test('cards stand off the background in every family and mode', () {
      for (final family in LarmThemeFamily.values) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          final theme = buildLarmTheme(
              family: family, brightness: brightness);
          expect(
            theme.cardTheme.color,
            isNot(theme.scaffoldBackgroundColor),
            reason: '$family $brightness: card blends into background',
          );
        }
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
      final controller =
          container.read(settingsControllerProvider.notifier);
      await controller.updateSoundMode(1);
      await controller.updateSnooze(10, 2);
      await controller.updateTheme(mode: 2, family: 4);
      await controller.updateTimeFormat(1);
      await controller.updateDefaultSound('zen_bowl');

      final box = container.read(settingsBoxProvider);
      final reloaded = loadSettings(box);
      expect(reloaded.soundMode, 1);
      expect(reloaded.snoozeMin, 10);
      expect(reloaded.snoozeCount, 2);
      expect(reloaded.themeMode, 2);
      expect(reloaded.family, 4);
      expect(reloaded.timeFormat, 1);
      expect(reloaded.defaultSoundId, 'zen_bowl');
    });
  });

  testWidgets('settings page applies theme, snooze, mode and format',
      (WidgetTester tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        await dashboardScope(dir: dir, suffix: 'page'),
      );
      await tester.pump();
      container =
          ProviderScope.containerOf(tester.element(find.text('Larm')));

      await tester.tap(find.byTooltip('Settings'));
      await spin(tester);
      expect(find.text('Settings'), findsWidgets);

      // Top-to-bottom only: ListView destroys scrolled-past rows, so never
      // navigate back up.
      await tester.tap(find.byTooltip('Increase Minutes'));
      await spin(tester, 4);
      expect(
          container.read(settingsControllerProvider).snoozeMin, 6);

      await tapVisible(tester, find.text('Always override'));
      await spin(tester, 4);
      expect(container.read(settingsControllerProvider).soundMode, 1);

      await tapVisible(tester, find.text('Ember Dusk'));
      await spin(tester, 4);
      expect(container.read(settingsControllerProvider).family, 4);

      await tapVisible(tester, find.text('24-hour'));
      await spin(tester, 4);
      expect(container.read(settingsControllerProvider).timeFormat, 1);
    });
  });
}
