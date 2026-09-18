import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

import '../../core/haptics.dart';
import '../../core/motion.dart';
import '../../core/notifications/scheduler.dart';
import '../../core/time/clock.dart';
import '../../data/models/alarm.dart';
import '../../data/models/larm_timer.dart';
import '../../data/repos/alarm_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/repos/timer_repo.dart';
import 'widgets/pulse_rings.dart';

/// Full-screen ringing page. Opened per fire (simultaneous fires stack as
/// sequential routes): dismissing the top reveals the next.
///
/// [autoAction] executes immediately on open: notification Stop/Snooze
/// action buttons route here and expect the effect, not just the UI.
class TriggerPage extends ConsumerStatefulWidget {
  const TriggerPage({
    super.key,
    this.alarmId,
    this.timerId,
    this.autoAction,
    this.snoozeRemaining,
  });

  final String? alarmId;
  final String? timerId;

  /// 'stop' | 'snooze' | null.
  final String? autoAction;
  final int? snoozeRemaining;

  @override
  ConsumerState<TriggerPage> createState() => _TriggerPageState();
}

class _TriggerPageState extends ConsumerState<TriggerPage> {
  static const _tabular = [FontFeature.tabularFigures()];

  bool _handled = false;
  bool _argsRead = false;
  String? _alarmId;
  String? _timerId;
  String? _autoAction;
  late int _remaining;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    _alarmId = widget.alarmId;
    _timerId = widget.timerId;
    _autoAction = widget.autoAction;
    final args = ModalRoute.of(context)?.settings.arguments;
    int? remaining;
    if (args is Map) {
      _alarmId ??= args['alarmId'] as String?;
      _timerId ??= args['timerId'] as String?;
      _autoAction ??= args['autoAction'] as String?;
      final rawRemaining = args['snoozeRemaining'];
      if (rawRemaining is int) remaining = rawRemaining;
    }
    _remaining = widget.snoozeRemaining ??
        remaining ??
        ref.read(settingsControllerProvider).snoozeCount;

    _buzz();
    final auto = _autoAction;
    if (auto == 'stop') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _stop());
    } else if (auto == 'snooze') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _snooze());
    }
  }

  Future<void> _buzz() async {
    try {
      await Vibration.vibrate(pattern: const [0, 400, 200, 400]);
    } catch (_) {
      // No vibrator / no platform channel: silent no-op.
    }
  }

  Alarm? get _alarm => _alarmId == null
      ? null
      : ref.read(alarmRepositoryProvider).getById(_alarmId!);

  LarmTimer? get _timer => _timerId == null
      ? null
      : ref.read(timerRepositoryProvider).getById(_timerId!);

  bool get _isTimer => _timerId != null;

  /// Runs [effect] once, then closes this fire (revealing any stacked next).
  /// Uses [Navigator.maybePop]: the page is normally pushed, but never trap
  /// the user if it ever ends up as the root route.
  Future<void> _finish(Future<void> Function() effect) async {
    if (_handled) return;
    _handled = true;
    try {
      await effect();
    } catch (_) {
      // Persistence already attempted; never trap the user on this page.
    }
    if (mounted) Navigator.maybePop(context);
  }

  Future<void> _stop() => _finish(() async {
        final settings = ref.read(settingsControllerProvider);
        final scheduler = ref.read(schedulerProvider);
        final now = DateTime.now();
        if (_isTimer) {
          final timer = _timer;
          if (timer == null) return;
          timer
            ..status = TimerStatus.done
            ..remainingSec = 0
            ..targetUtc = null;
          await ref.read(timerRepositoryProvider).upsert(timer);
          await scheduler.syncTimer(timer, settings, now: now);
        } else {
          final alarm = _alarm;
          if (alarm == null) return;
          if (alarm.repeat == AlarmRepeat.oneTime) {
            await ref.read(alarmRepositoryProvider).toggle(alarm.id, false);
            final updated =
                ref.read(alarmRepositoryProvider).getById(alarm.id);
            if (updated != null) {
              await scheduler.syncAlarm(updated, settings, now: now);
            }
          } else {
            // Repeating: stop this ring, schedule the next occurrence.
            await scheduler.syncAlarm(alarm, settings, now: now);
          }
        }
      });

  Future<void> _snooze() => _finish(() async {
        if (_remaining <= 0) return;
        final settings = ref.read(settingsControllerProvider);
        final scheduler = ref.read(schedulerProvider);
        final now = DateTime.now();
        if (_isTimer) {
          final timer = _timer;
          if (timer == null) return;
          timer
            ..status = TimerStatus.running
            ..targetUtc =
                now.toUtc().add(Duration(minutes: settings.snoozeMin))
            ..remainingSec = settings.snoozeMin * 60
            ..enabled = true;
          await ref.read(timerRepositoryProvider).upsert(timer);
          await scheduler.syncTimer(timer, settings, now: now);
        } else {
          final alarm = _alarm;
          if (alarm == null) return;
          await scheduler.snoozeAlarm(
            alarm,
            settings,
            now: now,
            remaining: _remaining,
          );
        }
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entrance = motionEnabled(context) ? 300.ms : Duration.zero;
    final settings = ref.watch(settingsControllerProvider);
    final use24h = settings.timeFormat == 1;
    final alarm = _isTimer ? null : _alarm;
    final timer = _isTimer ? _timer : null;
    final missing = _isTimer ? timer == null : alarm == null;

    final title = missing
        ? 'Gone'
        : _isTimer
            ? (timer!.title.isEmpty ? 'Timer' : timer.title)
            : (alarm!.title.isEmpty ? 'Alarm' : alarm.title);
    final timeLabel = missing
        ? ''
        : _isTimer
            ? 'Done'
            : fmtTime(DateTime.now(), use24h: use24h);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _stop();
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      PulseRings(size: 240, color: scheme.primary),
                      Icon(
                        Icons.notifications_active,
                        size: 80,
                        color: scheme.primary,
                      )
                          .animate()
                          .scale(duration: entrance)
                          .fadeIn(duration: entrance),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge,
                  )
                      .animate()
                      .fadeIn(duration: entrance)
                      .scale(duration: entrance),
                  if (timeLabel.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      timeLabel,
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(fontFeatures: _tabular),
                    ).animate().fadeIn(duration: entrance),
                  ],
                  if (missing) ...[
                    const SizedBox(height: 8),
                    const Text('This alarm no longer exists.'),
                  ],
                  const SizedBox(height: 32),
                  if (!missing) ...[
                    if (_remaining > 0)
                      Text('$_remaining snooze${_remaining == 1 ? '' : 's'} left',
                          style: Theme.of(context).textTheme.bodyMedium),
                    if (_remaining <= 0)
                      Text('No snoozes left',
                          style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(60),
                          textStyle:
                              Theme.of(context).textTheme.titleLarge,
                        ),
                        onPressed: _remaining > 0
                            ? () async {
                                await hapticTap();
                                await _snooze();
                              }
                            : null,
                        child: Text(
                            'Snooze ${settings.snoozeMin}m'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                          minimumSize: const Size.fromHeight(60),
                          textStyle:
                              Theme.of(context).textTheme.titleLarge,
                        ),
                        onPressed: () async {
                          await hapticConfirm();
                          await _stop();
                        },
                        child: const Text('Stop'),
                      ),
                    ),
                  ] else ...[
                    FilledButton(
                      onPressed: () => Navigator.maybePop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
