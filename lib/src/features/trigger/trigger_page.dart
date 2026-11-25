import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:vibration/vibration.dart';

import '../../core/audio/sounds.dart';
import '../../core/haptics.dart';
import '../../core/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/notifications/channels.dart';
import '../../core/notifications/fire_handoff.dart';
import '../../core/notifications/fire_launcher.dart';
import '../../core/notifications/fire_state.dart';
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

  AudioPlayer? _ringPlayer;
  Timer? _ringTimer;
  Timer? _autoCloseTimer;
  bool _ringStarted = false;
  int _ringMs = alarmRingMs;
  double _volume = 1;
  StreamSubscription<PendingFire>? _actionSub;

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
    final explicitRemaining =
        widget.snoozeRemaining != null || remaining != null;
    _remaining =
        widget.snoozeRemaining ??
        remaining ??
        ref.read(settingsControllerProvider).snoozeCount;

    final settings = ref.read(settingsControllerProvider);
    _ringMs = settings.ringDurationMs;
    _volume = settings.volumeFraction;

    // A snoozed fire carries its own remaining count; clear the badge now that
    // the delayed fire is actually on screen.
    final key = _timerId != null ? 'timer:$_timerId' : 'alarm:$_alarmId';
    if (!explicitRemaining) {
      final info = ref.read(snoozeStoreProvider)[key];
      if (info != null) {
        _remaining = info.remaining;
        unawaited(
          ref.read(snoozeStoreProvider.notifier).remove(
                info.kind,
                info.id,
              ),
        );
      }
    }

    // A late notification action must act on this page, not push a duplicate.
    _actionSub = FireHandoff.liveActions.listen((fire) {
      if (!mounted || _handled) return;
      if ('${fire.kind}:${fire.id}' != key) return;
      if (fire.autoAction == 'stop') {
        unawaited(_stop());
      } else if (fire.autoAction == 'snooze') {
        unawaited(_snooze());
      }
    });

    _buzz();
    unawaited(_startRingLifecycle());
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

  /// Starts the shared ring lifecycle from the real OS fire instant: an
  /// in-app audio fallback if the OEM dropped the notification, and an
  /// auto-close at the configured ring duration. Both use [lastFireAt] so a
  /// late UI mount does not extend the alarm beyond its notification window.
  Future<void> _startRingLifecycle() async {
    final started = await FireLauncher.lastFireAt() ?? DateTime.now().toUtc();
    if (!mounted) return;
    _watchNotificationSound(started);
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    final delay = (_ringMs - elapsed).clamp(0, _ringMs);
    _autoCloseTimer = Timer(Duration(milliseconds: delay), _autoClose);
  }

  /// The notification normally loops the tone with `FLAG_INSISTENT`. Some OEMs
  /// dismiss it as soon as the full-screen intent is consumed, so continue the
  /// same tone in-app for the rest of the configured ring window.
  void _watchNotificationSound(DateTime started) {
    final alarmId = _alarmId;
    final timerId = _timerId;
    if (alarmId == null && timerId == null) return;
    final notificationId = alarmId != null
        ? AlarmScheduler.notificationIdForAlarm(alarmId)
        : AlarmScheduler.notificationIdForTimer(timerId!);
    _ringTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (timer) async {
        if (!mounted || _ringStarted) {
          timer.cancel();
          return;
        }
        if (DateTime.now().difference(started).inMilliseconds >= _ringMs) {
          timer.cancel();
          return;
        }
        final active = await FireLauncher.isNotificationActive(notificationId);
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (!active) {
          _ringStarted = true;
          timer.cancel();
          await _startRingAudio(started);
        }
      },
    );
  }

  Future<void> _startRingAudio(DateTime started) async {
    final remaining = _ringMs - DateTime.now().difference(started).inMilliseconds;
    if (remaining <= 0) return;
    final selected = ref.read(settingsControllerProvider).defaultSoundId;
    final sound = selected != 'system' && isKnownSound(selected)
        ? selected
        : 'classic_chime';
    try {
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(_volume);
      await player.play(AssetSource('sounds/$sound.wav'));
      if (!mounted) {
        unawaited(player.stop());
        unawaited(player.dispose());
        return;
      }
      _ringPlayer = player;
      _ringTimer = Timer(Duration(milliseconds: remaining), _stopRingAudio);
    } catch (_) {
      // Missing asset/audio focus: the vibration still continues.
    }
  }

  void _stopRingAudio() {
    _ringTimer?.cancel();
    _ringTimer = null;
    final player = _ringPlayer;
    _ringPlayer = null;
    if (player != null) {
      unawaited(player.stop());
      unawaited(player.dispose());
    }
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    _autoCloseTimer?.cancel();
    _stopRingAudio();
    super.dispose();
  }

  Alarm? get _alarm => _alarmId == null
      ? null
      : ref.read(alarmRepositoryProvider).getById(_alarmId!);

  LarmTimer? get _timer => _timerId == null
      ? null
      : ref.read(timerRepositoryProvider).getById(_timerId!);

  bool get _isTimer => _timerId != null;

  String? get _payload {
    if (_alarmId != null) return alarmPayload(_alarmId!);
    if (_timerId != null) return timerPayload(_timerId!);
    return null;
  }

  int? get _notificationId {
    if (_alarmId != null) {
      return AlarmScheduler.notificationIdForAlarm(_alarmId!);
    }
    if (_timerId != null) {
      return AlarmScheduler.notificationIdForTimer(_timerId!);
    }
    return null;
  }

  /// Closes the ringing notification and full-screen handoff, replaces them
  /// with the silent "rang at …" summary, and returns Larm to the background.
  /// Safe to call from Stop, Snooze and the ring-duration auto-close.
  Future<void> _closeNativeRing() async {
    final id = _notificationId;
    final payload = _payload;
    if (id == null || payload == null) return;
    final at = await FireLauncher.lastFireAt() ?? DateTime.now().toUtc();
    await FireLauncher.finishRing(id: id, payload: payload, at: at);
    await FireLauncher.minimize();
  }

  /// Runs [effect] once, then closes this fire (revealing any stacked next).
  /// Uses [Navigator.maybePop]: the page is normally pushed, but never trap
  /// the user if it ever ends up as the root route.
  Future<void> _finish(Future<void> Function() effect) async {
    if (_handled) return;
    _handled = true;
    _autoCloseTimer?.cancel();
    try {
      await effect();
    } catch (_) {
      // Persistence already attempted; never trap the user on this page.
    }
    await _refreshArmedStatus();
    if (mounted) Navigator.maybePop(context);
  }

  /// The OS notification times itself out, but the Flutter page still needs
  /// to close when no action was taken (and the OS may not cancel its FSI).
  Future<void> _autoClose() => _finish(_closeNativeRing);

  Future<void> _refreshArmedStatus() async {
    try {
      await ref.read(schedulerProvider).refreshArmed(
            alarms: ref.read(alarmRepositoryProvider).all(),
            timers: ref.read(timerRepositoryProvider).all(),
            now: DateTime.now().toUtc(),
            snoozes: ref.read(snoozeStoreProvider),
          );
    } catch (_) {
      // Status-only; never break the fire action or the ringing UI.
    }
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
    await _closeNativeRing();
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
    await ref.read(snoozeStoreProvider.notifier).set(
          SnoozeInfo(
            kind: _isTimer ? 'timer' : 'alarm',
            id: _isTimer ? _timerId! : _alarmId!,
            untilUtc: now.toUtc().add(Duration(minutes: settings.snoozeMin)),
            remaining: _remaining - 1,
          ),
        );
    await _closeNativeRing();
  });

  @override
  Widget build(BuildContext context) {
    final entrance = motionEnabled(context) ? 300.ms : Duration.zero;
    final settings = ref.watch(settingsControllerProvider);
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
            : '${fmtTime(DateTime.now().toUtc())} UTC';

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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
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
                            PulseRings(size: 136, color: LarmPalette.pink),
                            Icon(
                                  LucideIcons.bellRing,
                                  size: 50,
                                  color: LarmPalette.pink,
                                )
                                .animate()
                                .scale(duration: entrance)
                                .fadeIn(duration: entrance),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 8),
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
                        const SizedBox(height: 12),
                        Text(
                          _remaining > 0
                              ? '$_remaining snooze${_remaining == 1 ? '' : 's'} left'
                              : 'No snoozes left',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
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
                        const SizedBox(height: 8),
                        FilledButton(
                          key: const Key('trigger-cancel-button'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
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
