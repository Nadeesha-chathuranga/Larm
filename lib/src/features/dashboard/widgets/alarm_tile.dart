import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../data/models/alarm.dart';
import '../../../data/models/larm_timer.dart';

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Short repeat description for list rows.
String repeatLabel(Alarm alarm) {
  switch (alarm.repeat) {
    case AlarmRepeat.daily:
      return 'Daily';
    case AlarmRepeat.weekdays:
      return 'Weekdays';
    case AlarmRepeat.custom:
      if (alarm.days.length != 7 || alarm.days.every((d) => !d)) {
        return 'Custom';
      }
      final parts = <String>[];
      for (var i = 0; i < 7; i++) {
        if (alarm.days[i]) parts.add(_dayNames[i]);
      }
      return parts.join(' ');
    case AlarmRepeat.oneTime:
    // ignore: no_default_cases
    default:
      return 'One-time';
  }
}

/// Alarm list row: title, next-fire subtitle, zone badge, repeat, toggle.
class AlarmTile extends StatelessWidget {
  const AlarmTile({
    super.key,
    required this.alarm,
    required this.subtitle,
    required this.onToggle,
    required this.onTap,
  });

  final Alarm alarm;
  final String subtitle;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: Text(
        alarm.title.isEmpty ? 'Alarm' : alarm.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle, style: textTheme.bodyLarge),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              alarm.isUtc ? 'UTC' : 'LOCAL',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            label:
                '${alarm.title.isEmpty ? 'Alarm' : alarm.title} ${alarm.enabled ? 'on' : 'off'}',
            toggled: alarm.enabled,
            excludeSemantics: true,
            child: _BouncySwitch(value: alarm.enabled, onChanged: onToggle),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Switch with a 180ms press bounce + haptic tick.
class _BouncySwitch extends StatefulWidget {
  const _BouncySwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_BouncySwitch> createState() => _BouncySwitchState();
}

class _BouncySwitchState extends State<_BouncySwitch> {
  double _scale = 1;

  Future<void> _tap(bool next) async {
    setState(() => _scale = 0.82);
    await hapticTap();
    widget.onChanged(next);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (mounted) setState(() => _scale = 1);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 90),
      child: Switch(value: widget.value, onChanged: _tap),
    );
  }
}

/// Timer list row: title, live remaining, pause/resume/reset controls.
class TimerTile extends StatelessWidget {
  const TimerTile({
    super.key,
    required this.title,
    required this.remainingLabel,
    required this.status,
    required this.onPause,
    required this.onResume,
    required this.onReset,
    required this.onTap,
  });

  final String title;
  final String remainingLabel;
  final int status;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onReset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final running = status == TimerStatus.running;
    final paused = status == TimerStatus.paused;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: const Icon(Icons.timer_outlined, size: 32),
      title: Text(title.isEmpty ? 'Timer' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(remainingLabel, style: textTheme.bodyLarge),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            IconButton(
              tooltip: 'Pause',
              icon: const Icon(Icons.pause),
              onPressed: () async {
                await hapticTap();
                onPause();
              },
            )
          else
            IconButton(
              tooltip: paused ? 'Resume' : 'Start',
              icon: const Icon(Icons.play_arrow),
              onPressed: () async {
                await hapticTap();
                onResume();
              },
            ),
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt),
            onPressed: () async {
              await hapticTap();
              onReset();
            },
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
