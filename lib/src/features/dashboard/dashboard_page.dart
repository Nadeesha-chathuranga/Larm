import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/haptics.dart';
import '../../core/nav.dart';
import '../../core/prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/notifications/background_handler.dart' show parseFirePayload;
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

String _clockString(DateTime dt, {required bool use24h}) {
  final base = fmtTime(dt, use24h: use24h);
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

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool? _exactOk;
  bool _launchChecked = false;
  bool _legacyNoticeChecked = false;

  @override
  void initState() {
    super.initState();
    _refreshExactStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cold start from a killed app via notification tap: open the fire.
    if (_launchChecked) return;
    _launchChecked = true;
    _openLaunchFire();
    _checkLegacyNotice();
  }

  Future<void> _openLaunchFire() async {
    try {
      final details = await NotificationService.plugin
          .getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return;
      final fire = parseFirePayload(details?.notificationResponse?.payload);
      if (fire == null || !mounted) return;
      larmNavigatorKey.currentState?.pushNamed(
        '/trigger',
        arguments: <String, Object?>{'${fire.kind}Id': fire.id},
      );
    } catch (_) {
      // Best effort; taps also route through onBgAction when alive.
    }
  }

  /// Exact-alarm status check. Never throws: platform channels are absent in
  /// widget tests and on desktop, where exact alarms are assumed available.
  Future<void> _refreshExactStatus() async {
    bool ok = true;
    try {
      ok = await NotificationService.canScheduleExact();
    } catch (_) {
      ok = true;
    }
    if (mounted) setState(() => _exactOk = ok);
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
    await _refreshExactStatus();
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
            settings: ref.read(settingsControllerProvider),
            now: DateTime.now().toUtc(),
          );
    } catch (_) {
      // Status notice is best effort; the fire schedule is already synced.
    }
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
    await _refreshExactStatus();
    if (!mounted) return;
    if (!permissionsOk || !schedulingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alarm may not fire: allow notifications and exact alarms.',
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
    await _refreshArmed();
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
    await _refreshArmed();
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
    final settings = ref.watch(settingsControllerProvider);
    final use24h = settings.timeFormat == 1;
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
      body: StreamBuilder<int>(
        stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
        builder: (context, _) {
          final now = DateTime.now().toUtc();
          return ValueListenableBuilder(
            valueListenable: alarmRepo.listenable(),
            builder: (context, alarmBox, child) {
              return ValueListenableBuilder(
                valueListenable: timerRepo.listenable(),
                builder: (context, timerBox, child) {
                  return _body(context, now, use24h);
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

  Widget _body(BuildContext context, DateTime now, bool use24h) {
    final alarms = ref.read(alarmRepositoryProvider).all();
    final timerRepo = ref.read(timerRepositoryProvider);
    final timers = timerRepo.all();

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
          'Next · ${fmtTime(nearestFinal, use24h: use24h)} · ${_countdownLabel(remaining.isNegative ? Duration.zero : remaining)}';
    }

    final showBanner = _exactOk == false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        HybridHero(
          dateLabel: DateFormat('EEE, MMM d').format(utc),
          primaryTime: _clockString(utc, use24h: use24h),
          primaryLabel: 'UTC',
          ringProgress: ring,
          nextLabel: nextLabel,
        ),
        if (showBanner) ...[
          const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        if (alarms.isEmpty && timers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
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
                bottom: i == alarms.length - 1 ? 0 : 12,
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
                    subtitle: _alarmSubtitle(alarms[i], utc, use24h),
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
                bottom: i == timers.length - 1 ? 0 : 12,
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
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
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

  String _alarmSubtitle(Alarm alarm, DateTime utc, bool use24h) {
    final next = nextOccurrence(alarm, fromUtc: utc);
    final fire = next ?? oneTimeInstantUtc(alarm);
    final repeat = repeatLabel(alarm);
    final when = fire == null
        ? repeat
        : '${fmtDateTime(fire, use24h: use24h)} · $repeat';
    if (!alarm.enabled) return '$when · Off';
    if (next == null) return '$when · Passed';
    return when;
  }
}
