import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sounds.dart';
import '../../core/haptics.dart';
import '../../core/motion.dart';
import '../../core/notifications/scheduler.dart';
import '../../core/notifications/service.dart';
import '../../core/theme/family.dart';
import '../../core/theme/tokens.dart';
import '../../data/repos/alarm_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/repos/timer_repo.dart';
import '../editor/widgets/sound_sheet.dart';

/// Settings: sound mode, snooze, theme, time format, default tone.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool? _policyAccess;

  @override
  void initState() {
    super.initState();
    _refreshPolicy();
  }

  Future<void> _refreshPolicy() async {
    try {
      final ok = await NotificationService.hasPolicyAccess();
      if (mounted) setState(() => _policyAccess = ok);
    } catch (_) {
      if (mounted) setState(() => _policyAccess = false);
    }
  }

  Future<void> _resyncAll() async {
    final scheduler = ref.read(schedulerProvider);
    final settings = ref.read(settingsControllerProvider);
    try {
      await scheduler.syncAll(
        alarms: ref.read(alarmRepositoryProvider).all(),
        timers: ref.read(timerRepositoryProvider).all(),
        settings: settings,
        now: DateTime.now(),
      );
    } catch (_) {
      // Platform channels absent (tests/desktop): ignore.
    }
  }

  Future<void> _setSoundMode(int mode) async {
    await hapticTap();
    await ref.read(settingsControllerProvider.notifier).updateSoundMode(mode);
    if (mode == 1) {
      // DND bypass only works with notification policy access.
      try {
        await NotificationService.requestPolicyAccess();
      } catch (_) {
        // Best effort; hint below explains the manual path.
      }
      await _refreshPolicy();
    }
    await _resyncAll();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _group(context, children: [
            _label(context, 'Sound mode'),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Follow system')),
                ButtonSegment(value: 1, label: Text('Always override')),
              ],
              selected: {settings.soundMode},
              onSelectionChanged: (selected) =>
                  _setSoundMode(selected.first),
            ),
            const SizedBox(height: 8),
            Text(
              settings.soundMode == 1
                  ? 'Forces the alarm sound even in silent / Do Not Disturb.'
                      '${_policyAccess == false ? ' Allow DND access in system settings for bypass to work.' : ''}'
                  : 'Alarms respect silent mode and Do Not Disturb.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ]),
          _group(context, children: [
            _label(context, 'Snooze'),
            Row(
              children: [
                Expanded(
                  child: _Stepper(
                    label: 'Minutes',
                    value: settings.snoozeMin,
                    min: 1,
                    max: 30,
                    onChanged: (v) async {
                      await hapticTap();
                      await controller.updateSnooze(
                          v, settings.snoozeCount);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stepper(
                    label: 'Times',
                    value: settings.snoozeCount,
                    min: 0,
                    max: 10,
                    onChanged: (v) async {
                      await hapticTap();
                      await controller.updateSnooze(settings.snoozeMin, v);
                    },
                  ),
                ),
              ],
            ),
          ]),
          _group(context, children: [
            _label(context, 'Appearance'),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('System')),
                ButtonSegment(value: 1, label: Text('Light')),
                ButtonSegment(value: 2, label: Text('Dark')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selected) async {
                await hapticTap();
                await controller.updateTheme(
                    mode: selected.first, family: settings.family);
              },
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.4,
              ),
              itemCount: LarmThemeFamily.values.length,
              itemBuilder: (context, index) {
                final family = LarmThemeFamily.values[index];
                final selected = settings.family == index;
                final light = larmLightScheme(family);
                final dark = larmDarkScheme(family);
                final brightness = Theme.of(context).brightness;
                final scheme =
                    brightness == Brightness.dark ? dark : light;
                return GestureDetector(
                  onTap: () async {
                    await hapticTap();
                    await controller.updateTheme(
                        mode: settings.themeMode, family: index);
                  },
                  child: AnimatedContainer(
                    duration: animDuration(context, 250),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: selected ? 3 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _swatch(light.primary, 18),
                            const SizedBox(width: 6),
                            _swatch(dark.primary, 18),
                            const SizedBox(width: 6),
                            _swatch(scheme.onSurface, 18),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          family.displayName,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                color: scheme.onSurface,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ]),
          _group(context, children: [
            _label(context, 'Time format'),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('12-hour')),
                ButtonSegment(value: 1, label: Text('24-hour')),
              ],
              selected: {settings.timeFormat},
              onSelectionChanged: (selected) async {
                await hapticTap();
                await controller.updateTimeFormat(selected.first);
              },
            ),
          ]),
          _group(context, children: [
            _label(context, 'Default alarm tone'),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 4),
                title: Text(
                  soundLabel(settings.defaultSoundId),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  soundCategory(settings.defaultSoundId),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await hapticTap();
                  if (!context.mounted) return;
                  final picked = await showSoundPickerSheet(
                    context,
                    currentId: settings.defaultSoundId,
                  );
                  if (picked != null && context.mounted) {
                    await controller.updateDefaultSound(picked);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Per-alarm tones are picked in the editor; override mode always '
              'uses the bypass channel for reliability.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ]),
        ],
      ),
    );
  }
}

/// Grouped settings section card.
Widget _group(BuildContext context, {required List<Widget> children}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

Widget _label(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    ),
  );
}

Widget _swatch(Color color, double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
    ),
  );
}

/// Labeled stepper with a rolling number transition.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Decrease $label',
                  icon: const Icon(Icons.remove),
                  onPressed: value > min ? () => onChanged(value - 1) : null,
                ),
                AnimatedSwitcher(
                  duration: animDuration(context, 200),
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.4),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(
                        opacity: animation, child: child),
                  ),
                  child: Text(
                    '$value',
                    key: ValueKey(value),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Increase $label',
                  icon: const Icon(Icons.add),
                  onPressed: value < max ? () => onChanged(value + 1) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
