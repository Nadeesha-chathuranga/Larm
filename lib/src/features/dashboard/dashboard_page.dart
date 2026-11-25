import 'dart:async';

import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/haptics.dart';
import '../../core/prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/notifications/background_handler.dart'
    show parseAlarmAction, parseFirePayload;
import '../../core/notifications/fire_handoff.dart';
import '../../core/notifications/fire_state.dart';
import '../../core/notifications/scheduler.dart';
import '../../core/notifications/service.dart';
import '../../core/time/clock.dart';
import '../../data/models/alarm.dart';
import '../../data/models/larm_timer.dart';
import '../../data/repos/alarm_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/repos/timer_repo.dart';
import '../editor/editor_page.dart';
import 'widgets/alarm_tile.dart';
import 'widgets/hybrid_hero.dart';

String _clockString(DateTime dt) {
  final base = fmtTime(dt);
  return '$base:${dt.second.toString().padLeft(2, '0')}';
}

String _remainingLabel(LarmTimer timer, DateTime now) {
  int secs;
  if (timer.status == TimerStatus.running && timer.targetUtc != null) {
    secs = timer.targetUtc!
        .toUtc()
        .difference(now.toUtc())
        .inSeconds
        .clamp(0, 1 << 31);
  } else {
    secs = timer.remainingSec;
  }
  final h = secs ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  final s = secs % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

String _countdownLabel(Duration d) {
  if (d.inHours > 0) return 'in ${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return 'in ${d.inMinutes}m ${d.inSeconds % 60}s';
  return 'in ${d.inSeconds}s';
}

/// Dashboard: clock hero, permission banner, alarm/timer list, add button.
///
/// Ticks once per second for digital readouts; the analog face repaints
/// itself at display rate inside a [RepaintBoundary].
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with WidgetsBindingObserver {
  bool? _exactOk;
  bool? _fsiOk;
  bool _launchChecked = false;
  bool _legacyNoticeChecked = false;

  /// The whole app is event-driven while backgrounded; this one-second tick
  /// only exists for the visible dashboard and is paused in the background.
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
    _refreshPermissionStatus();
    unawaited(_loadSnoozes());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopClock();
    _tick.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClock();
      unawaited(_loadSnoozes());
      unawaited(_refreshArmed());
    } else {
      _stopClock();
    }
  }

  void _startClock() {
    if (_clockTimer != null) return;
    _tick.value++;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick.value++;
    });
  }

  void _stopClock() {
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cold start from a killed app via notification tap: open the fire.
    if (_launchChecked) return;
    _launchChecked = true;
    _openLaunchFire();
    _checkLegacyNotice();
    // The shade must always show the current closest fire, even if this is a
    // cold start after a fire with no user action.
    unawaited(_refreshArmed());
  }

  Future<void> _openLaunchFire() async {
    try {
      final details = await NotificationService.plugin
          .getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return;
      final response = details?.notificationResponse;
      final fire = parseFirePayload(response?.payload);
      if (fire == null || !mounted) return;
      final action = parseAlarmAction(response?.actionId);
      final auto =
          action != null && (action.kind == 'stop' || action.kind == 'snooze')
              ? action.kind
              : null;
      await FireHandoff.enqueue(
        kind: fire.kind,
        id: fire.id,
        autoAction: auto,
      );
    } catch (_) {
      // Best effort; taps also route through onBgAction when alive.
    }
  }

  /// Permission status check. Never throws: platform channels are absent in
  /// widget tests and on desktop, where both are assumed available.
  Future<void> _refreshPermissionStatus() async {
    bool exact = true;
    bool fullScreen = true;
    try {
      exact = await NotificationService.canScheduleExact();
    } catch (_) {
      exact = true;
    }
    try {
      fullScreen = await NotificationService.canUseFullScreenIntent();
    } catch (_) {
      fullScreen = true;
    }
    if (mounted) {
      setState(() {
        _exactOk = exact;
        _fsiOk = fullScreen;
      });
    }
  }

  /// Explains and opens the Android 14+ full-screen intent setting. Without
  /// this toggle the system only shows a heads-up/notification-shade alert.
  Future<void> _enableFullScreen() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Full-screen alarms'),
        content: const Text(
          'Android can show an alarm only in the notification shade. Turn on '
          'full-screen intent for Larm so a ringing alarm takes over the '
          'screen, even when it is locked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final opened = await NotificationService.openFullScreenIntentSettings();
    if (!opened) {
      // OEM fallback: the generic list still exposes the toggle.
      try {
        await NotificationService.requestFullScreenIntent();
      } catch (_) {
        // Best effort; the banner stays until the toggle is actually on.
      }
    }
    await _refreshPermissionStatus();
  }

  /// One-time explanation after the UTC-only migration disabled old Local
  /// alarms. Never blocks the UI and is only shown once.
  Future<void> _checkLegacyNotice() async {
    if (_legacyNoticeChecked || !mounted) return;
    _legacyNoticeChecked = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(legacyLocalDisabledKey) != true) return;
      await prefs.remove(legacyLocalDisabledKey);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('UTC-only update'),
          content: const Text(
            'Larm now uses UTC time everywhere. Old Local alarms were turned '
            'off. Recreate them with the UTC times you want.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Best effort; absence of the notice never affects alarm behavior.
    }
  }

  Future<void> _enableAlarms() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exact alarms'),
        content: const Text(
          'Larm needs permission to fire alarms at the exact time, even in '
          'Doze mode, and to ignore battery optimizations so alarms survive '
          'overnight. Without these, alarms may arrive late or not at all.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await NotificationService.requestPostNotifications();
      await NotificationService.requestExactAlarms();
      await NotificationService.requestFullScreenIntent();
      // OEM battery killers (Samsung/Xiaomi/…): without this exemption the
      // OS may stop exact alarms overnight. Best effort; no status query —
      // the Play-friendly path is user education, not a hard requirement.
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {
      // Best effort; banner reappears if still denied.
    }
    await _resyncAll();
    await _refreshPermissionStatus();
  }

  Future<void> _resyncAll() async {
    final scheduler = ref.read(schedulerProvider);
    final settings = ref.read(settingsControllerProvider);
    final alarms = ref.read(alarmRepositoryProvider).all();
    final timers = ref.read(timerRepositoryProvider).all();
    try {
      await scheduler.syncAll(
        alarms: alarms,
        timers: timers,
        settings: settings,
        now: DateTime.now().toUtc(),
        snoozes: ref.read(snoozeStoreProvider),
      );
    } catch (_) {
      // Offline from platform channels (tests/desktop): ignore.
    }
  }

  Future<void> _refreshArmed() async {
    try {
      await ref.read(schedulerProvider).refreshArmed(
            alarms: ref.read(alarmRepositoryProvider).all(),
            timers: ref.read(timerRepositoryProvider).all(),
            now: DateTime.now().toUtc(),
            snoozes: ref.read(snoozeStoreProvider),
          );
    } catch (_) {
      // Status notice is best effort; the fire schedule is already synced.
    }
  }

  /// Reloads snooze metadata after a cold start or resume, dropping entries
  /// whose alarm/timer was deleted or whose snooze instant already passed.
  Future<void> _loadSnoozes() async {
    try {
      final notifier = ref.read(snoozeStoreProvider.notifier);
      // main() already hydrated the store on cold start. Only fall back to
      // SharedPreferences when the in-memory store is empty, so a test/app
      // override is not clobbered and a second read is avoided on resume.
      if (ref.read(snoozeStoreProvider).isEmpty) await notifier.load();
      await _pruneSnoozes();
      await _refreshArmed();
    } catch (_) {
      // Snooze badges and the shade countdown are status-only.
    }
  }

  Future<void> _pruneSnoozes() async {
    final now = DateTime.now().toUtc();
    final alive = <String>{
      for (final alarm in ref.read(alarmRepositoryProvider).all())
        'alarm:${alarm.id}',
      for (final timer in ref.read(timerRepositoryProvider).all())
        'timer:${timer.id}',
    };
    await ref
        .read(snoozeStoreProvider.notifier)
        .prune(aliveKeys: alive, now: now);
  }

  Future<void> _toggleAlarm(Alarm alarm, bool on) async {
    final permissionsOk = await NotificationService.ensureFirePermissions();
    await ref.read(alarmRepositoryProvider).toggle(alarm.id, on);
    SyncOutcome outcome = SyncOutcome.cancelled;
    var schedulingOk = true;
    try {
      final updated = ref.read(alarmRepositoryProvider).getById(alarm.id);
      if (updated != null) {
        outcome = await ref
            .read(schedulerProvider)
            .syncAlarm(
              updated,
              ref.read(settingsControllerProvider),
              now: DateTime.now().toUtc(),
            );
      }
    } catch (_) {
      schedulingOk = false;
    }
    await _refreshArmed();
    await _refreshPermissionStatus();
    if (!mounted) return;
    if (!permissionsOk || !schedulingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alarm may not pop up: allow notifications, exact alarms and '
            'full-screen display.',
          ),
        ),
      );
    } else if (outcome == SyncOutcome.expired) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('That time already passed')));
    }
  }

  Future<void> _deleteAlarm(Alarm alarm) async {
    final wasEnabled = alarm.enabled;
    await ref.read(alarmRepositoryProvider).delete(alarm.id);
    try {
      await ref
          .read(schedulerProvider)
          .syncAlarm(
            alarm..enabled = false,
            ref.read(settingsControllerProvider),
            now: DateTime.now().toUtc(),
          );
    } catch (_) {
      // Persistence already done; scheduling is best effort here.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Alarm deleted'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            alarm.enabled = wasEnabled;
            await ref.read(alarmRepositoryProvider).upsert(alarm);
            await _resyncAll();
          },
        ),
      ),
    );
    // Status-only cleanup; never hold the undo snackbar behind SharedPreferences.
    unawaited(_pruneSnoozes());
    unawaited(_refreshArmed());
  }

  Future<void> _deleteTimer(LarmTimer timer) async {
    final prevStatus = timer.status;
    final prevTarget = timer.targetUtc;
    final prevRemaining = timer.remainingSec;
    final prevEnabled = timer.enabled;
    await ref.read(timerRepositoryProvider).delete(timer.id);
    try {
      await ref
          .read(schedulerProvider)
          .syncTimer(
            timer
              ..status = TimerStatus.idle
              ..targetUtc = null,
            ref.read(settingsControllerProvider),
            now: DateTime.now().toUtc(),
          );
    } catch (_) {
      // Persistence already done; scheduling is best effort here.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Timer deleted'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            timer
              ..status = prevStatus
              ..targetUtc = prevTarget
              ..remainingSec = prevRemaining
              ..enabled = prevEnabled;
            await ref.read(timerRepositoryProvider).upsert(timer);
            await _resyncAll();
          },
        ),
      ),
    );
    unawaited(_pruneSnoozes());
    unawaited(_refreshArmed());
  }

  Future<void> _timerControl(Future<LarmTimer?> Function() action) async {
    final updated = await action();
    if (updated == null) return;
    try {
      await ref
          .read(schedulerProvider)
          .syncTimer(
            updated,
            ref.read(settingsControllerProvider),
            now: DateTime.now().toUtc(),
          );
    } catch (_) {
      // Persistence already done; scheduling is best effort here.
    }
    await _refreshArmed();
  }

  @override
  Widget build(BuildContext context) {
    final alarmRepo = ref.watch(alarmRepositoryProvider);
    final timerRepo = ref.watch(timerRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Larm'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(LucideIcons.settings2),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: _tick,
        builder: (context, _, child) {
          final now = DateTime.now().toUtc();
          return ValueListenableBuilder(
            valueListenable: alarmRepo.listenable(),
            builder: (context, alarmBox, child) {
              return ValueListenableBuilder(
                valueListenable: timerRepo.listenable(),
                builder: (context, timerBox, child) {
                  return _body(context, now);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: OpenContainer(
        closedShape: const CircleBorder(),
        closedColor: Theme.of(context).colorScheme.primaryContainer,
        openBuilder: (context, action) => const EditorPage(),
        closedBuilder: (_, open) => NeonFab(
          tooltip: 'New alarm or timer',
          icon: LucideIcons.plus,
          onPressed: () async {
            await hapticTap();
            open();
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DateTime now) {
    final alarms = ref.read(alarmRepositoryProvider).all();
    final timerRepo = ref.read(timerRepositoryProvider);
    final timers = timerRepo.all();
    final snoozes = ref.watch(snoozeStoreProvider);

    final utc = now.toUtc();

    tz.TZDateTime? nearest;
    for (final alarm in alarms) {
      if (!alarm.enabled) continue;
      final next = nextOccurrence(alarm, fromUtc: utc);
      if (next == null) continue;
      if (nearest == null || next.isBefore(nearest)) nearest = next;
    }
    final nearestFinal = nearest;

    double? ring;
    String? nextLabel;
    if (nearestFinal != null) {
      final remaining = nearestFinal.difference(utc);
      const window = Duration(hours: 12);
      ring = remaining <= Duration.zero
          ? 1.0
          : (1 - remaining.inSeconds / window.inSeconds).clamp(0.0, 1.0);
      nextLabel =
          'Next · ${fmtTime(nearestFinal)} · ${_countdownLabel(remaining.isNegative ? Duration.zero : remaining)}';
    }

    final showBanner = _exactOk == false;
    final showFsiBanner = _fsiOk == false;

    // Extra bottom inset keeps the last alarm clear of the + button.
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        HybridHero(
          dateLabel: DateFormat('EEE, MMM d').format(utc),
          primaryTime: _clockString(utc),
          primaryLabel: 'UTC',
          ringProgress: ring,
          nextLabel: nextLabel,
        ),
        if (showBanner) ...[
          const SizedBox(height: 8),
          GlassCard(
            tint: LarmPalette.coral.withValues(alpha: 0.08),
            accent: LarmPalette.coral,
            glow: false,
            child: ListTile(
              leading: const GlassIcon(
                icon: LucideIcons.bellOff,
                color: LarmPalette.coral,
                boxSize: 40,
              ),
              title: const Text('Exact alarms off'),
              subtitle: const Text('Alarms may arrive late.'),
              trailing: FilledButton(
                onPressed: _enableAlarms,
                child: const Text('Enable'),
              ),
            ),
          ),
        ],
        if (showFsiBanner) ...[
          const SizedBox(height: 8),
          GlassCard(
            tint: LarmPalette.amber.withValues(alpha: 0.08),
            accent: LarmPalette.amber,
            glow: false,
            child: ListTile(
              leading: const GlassIcon(
                icon: LucideIcons.bellRing,
                color: LarmPalette.amber,
                boxSize: 40,
              ),
              title: const Text('Full-screen alarms off'),
              subtitle: const Text(
                'Alarms only show in the shade. Let Larm take over the screen '
                'when an alarm rings.',
              ),
              trailing: FilledButton(
                onPressed: _enableFullScreen,
                child: const Text('Enable'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (alarms.isEmpty && timers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                GlassIcon(
                  icon: LucideIcons.alarmClockOff,
                  color: LarmPalette.violet,
                  size: 34,
                  boxSize: 76,
                ),
                const SizedBox(height: 12),
                NeonText(
                  'No alarms yet — tap + to add one.',
                  style:
                      Theme.of(context).textTheme.titleMedium ??
                      const TextStyle(fontSize: 16),
                  gradient: LarmPalette.hotGradient,
                  glow: LarmPalette.pink,
                ),
              ],
            ),
          ),
        if (alarms.isNotEmpty) ...[
          _listHeader(context, 'Alarms', alarms.length),
          for (var i = 0; i < alarms.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == alarms.length - 1 ? 0 : 8,
              ),
              child: Dismissible(
                key: ValueKey('alarm-${alarms[i].id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(LucideIcons.trash2, color: LarmPalette.coral),
                ),
                onDismissed: (_) => _deleteAlarm(alarms[i]),
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  child: AlarmTile(
                    alarm: alarms[i],
                    subtitle: _alarmSubtitle(alarms[i], utc),
                    snoozeLabel: _snoozeTileLabel(
                      'alarm',
                      alarms[i].id,
                      snoozes,
                      utc,
                    ),
                    onToggle: (on) => _toggleAlarm(alarms[i], on),
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/editor',
                      arguments: {'alarmId': alarms[i].id},
                    ),
                  ),
                ),
              ),
            ),
        ],
        if (timers.isNotEmpty) ...[
          _listHeader(context, 'Timers', timers.length),
          for (var i = 0; i < timers.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == timers.length - 1 ? 0 : 8,
              ),
              child: Dismissible(
                key: ValueKey('timer-${timers[i].id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(LucideIcons.trash2, color: LarmPalette.coral),
                ),
                onDismissed: (_) => _deleteTimer(timers[i]),
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  child: TimerTile(
                    title: timers[i].title,
                    remainingLabel: _remainingLabel(timers[i], utc),
                    snoozeLabel: _snoozeTileLabel(
                      'timer',
                      timers[i].id,
                      snoozes,
                      utc,
                    ),
                    status: timers[i].status,
                    onPause: () => _timerControl(
                      () => timerRepo.pause(timers[i].id, DateTime.now().toUtc()),
                    ),
                    onResume: () => _timerControl(
                      () => timerRepo.start(timers[i].id, DateTime.now().toUtc()),
                    ),
                    onReset: () =>
                        _timerControl(() => timerRepo.reset(timers[i].id)),
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/editor',
                      arguments: {'timerId': timers[i].id},
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// Section header with a neon accent bar and item count.
  Widget _listHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LarmPalette.hotGradient,
              boxShadow: const [
                BoxShadow(color: Color(0x335FE3FF), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$title · $count',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: LarmPalette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Tile badge for a snoozed fire. The native shade notice uses the same
  /// wording so the dashboard and notification panel never disagree.
  String? _snoozeTileLabel(
    String kind,
    String id,
    Map<String, SnoozeInfo> snoozes,
    DateTime utc,
  ) {
    final info = snoozes['$kind:$id'];
    if (info == null || !info.untilUtc.isAfter(utc)) return null;
    final countdown = armedCountdownLabel(info.untilUtc.difference(utc));
    return '${snoozeRemainingLabel(info.remaining)} · $countdown';
  }

  String _alarmSubtitle(Alarm alarm, DateTime utc) {
    final next = nextOccurrence(alarm, fromUtc: utc);
    final fire = next ?? oneTimeInstantUtc(alarm);
    final repeat = repeatLabel(alarm);
    final when = fire == null
        ? repeat
        : '${fmtDateTime(fire)} · $repeat';
    if (!alarm.enabled) return '$when · Off';
    if (next == null) return '$when · Passed';
    return when;
  }
}
