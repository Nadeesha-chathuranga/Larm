import 'package:material_ui/material_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:vibration/vibration.dart';

import '../../core/audio/sounds.dart';
import '../../core/haptics.dart';
import '../../core/motion.dart';
import '../../core/theme/tokens.dart';
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
    _remaining =
        widget.snoozeRemaining ??
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

  /// Every alarm and timer uses the vibration pattern chosen in Settings.
  Future<void> _buzz() async {
    final pattern = vibrationById(
      ref.read(settingsControllerProvider).defaultVibId,
    );
    if (pattern.id == 'off') return;
    try {
      if (pattern.pattern.isEmpty) {
        await Vibration.vibrate(duration: pattern.duration);
      } else {
        await Vibration.vibrate(pattern: pattern.pattern);
      }
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
    try {
      await ref.read(schedulerProvider).refreshArmed(
            alarms: ref.read(alarmRepositoryProvider).all(),
            timers: ref.read(timerRepositoryProvider).all(),
            settings: ref.read(settingsControllerProvider),
            now: DateTime.now().toUtc(),
          );
    } catch (_) {
      // Status notice is best effort; the fire action already completed.
    }
    if (mounted) Navigator.maybePop(context);
  }

  Future<void> _stop() => _finish(() async {
    final settings = ref.read(settingsControllerProvider);
    final scheduler = ref.read(schedulerProvider);
    final now = DateTime.now().toUtc();
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
        final updated = ref.read(alarmRepositoryProvider).getById(alarm.id);
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
    final now = DateTime.now().toUtc();
    if (_isTimer) {
      final timer = _timer;
      if (timer == null) return;
      timer
        ..status = TimerStatus.running
        ..targetUtc = now.toUtc().add(Duration(minutes: settings.snoozeMin))
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
    final subtitle = missing
        ? 'This alarm no longer exists.'
        : _isTimer
            ? 'Done'
            : '${fmtTime(DateTime.now().toUtc(), use24h: use24h)} UTC';

    final titleStyle = (Theme.of(context).textTheme.displayMedium ??
            const TextStyle(fontSize: 45))
        .copyWith(
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: -0.8,
    );
    final subtitleStyle = (Theme.of(context).textTheme.titleLarge ??
            const TextStyle(fontSize: 22))
        .copyWith(fontFeatures: _tabular, fontWeight: FontWeight.w600);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _stop();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  tint: LarmPalette.glassStrong,
                  accent: LarmPalette.pink,
                  glow: true,
                  borderRadius: const BorderRadius.all(Radius.circular(32)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PulseRings(size: 180, color: LarmPalette.pink),
                            Icon(
                                  LucideIcons.bellRing,
                                  size: 64,
                                  color: LarmPalette.pink,
                                )
                                .animate()
                                .scale(duration: entrance)
                                .fadeIn(duration: entrance),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      NeonText(
                            title,
                            textAlign: TextAlign.center,
                            style: titleStyle,
                            gradient: LarmPalette.hotGradient,
                            glow: LarmPalette.pink,
                          )
                          .animate()
                          .fadeIn(duration: entrance)
                          .slideY(
                            begin: 0.08,
                            end: 0,
                            duration: entrance,
                          ),
                      const SizedBox(height: 10),
                      NeonText(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: subtitleStyle,
                        gradient: LarmPalette.sunsetGradient,
                        glow: LarmPalette.amber,
                      ).animate().fadeIn(duration: entrance),
                      if (missing) ...[
                        const SizedBox(height: 24),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor: LarmPalette.violet,
                            foregroundColor: LarmPalette.backgroundDeep,
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => Navigator.maybePop(context),
                          child: const Text('Close'),
                        ),
                      ] else ...[
                        const SizedBox(height: 18),
                        Text(
                          _remaining > 0
                              ? '$_remaining snooze${_remaining == 1 ? '' : 's'} left'
                              : 'No snoozes left',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            textStyle: Theme.of(context).textTheme.titleMedium,
                            backgroundColor: LarmPalette.violet.withValues(
                              alpha: 0.28,
                            ),
                            foregroundColor: LarmPalette.text,
                            side: const BorderSide(
                              color: LarmPalette.violet,
                              width: 1.2,
                            ),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: _remaining > 0
                              ? () async {
                                  await hapticTap();
                                  await _snooze();
                                }
                              : null,
                          child: Text('Snooze ${settings.snoozeMin}m'),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          key: const Key('trigger-cancel-button'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(60),
                            textStyle: (Theme.of(context)
                                        .textTheme
                                        .titleLarge ??
                                    const TextStyle(fontSize: 22))
                                .copyWith(fontWeight: FontWeight.w700),
                            backgroundColor: LarmPalette.cyan,
                            foregroundColor: LarmPalette.backgroundDeep,
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () async {
                            await hapticConfirm();
                            await _stop();
                          },
                          child: const Text('Cancel'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
