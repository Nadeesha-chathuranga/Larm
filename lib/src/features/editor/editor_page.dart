import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/haptics.dart';
import '../../core/notifications/scheduler.dart';
import '../../core/notifications/service.dart';
import '../../core/theme/tokens.dart';
import '../../core/time/clock.dart';
import '../../data/models/alarm.dart';
import '../../data/models/larm_timer.dart';
import '../../data/repos/alarm_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/repos/timer_repo.dart';
import '../dashboard/widgets/analog_painter.dart';
import 'widgets/date_picker.dart';
import 'widgets/wheel_picker.dart';

enum _Kind { alarm, timer }

/// Alarm + timer editor. Creates new entries or edits existing ones
/// (resolved from constructor ids or route arguments).
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key, this.alarmId, this.timerId});

  final String? alarmId;
  final String? timerId;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  static const _uuid = Uuid();

  bool _resolved = false;
  bool _isTimer = false;
  bool _creating = true;
  String? _editAlarmId;
  String? _editTimerId;

  late final TextEditingController _title;
  int _hour = 8;
  int _minute = 0;
  DateTime _date = DateTime.now().toUtc();

  int _tHour = 0;
  int _tMin = 5;
  int _tSec = 0;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;

    String? alarmId = widget.alarmId;
    String? timerId = widget.timerId;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      alarmId ??= args['alarmId'] as String?;
      timerId ??= args['timerId'] as String?;
    }

    final now = DateTime.now().toUtc();
    _hour = (now.hour + 1) % 24;
    _minute = 0;
    _date = DateTime.utc(now.year, now.month, now.day);

    if (alarmId != null) {
      final alarm = ref.read(alarmRepositoryProvider).getById(alarmId);
      if (alarm != null) {
        _creating = false;
        _isTimer = false;
        _editAlarmId = alarm.id;
        _title.text = alarm.title;
        _hour = alarm.hour;
        _minute = alarm.minute;
        if (alarm.year != null && alarm.month != null && alarm.day != null) {
          _date = DateTime.utc(alarm.year!, alarm.month!, alarm.day!);
        }
        return;
      }
    }
    if (timerId != null) {
      final timer = ref.read(timerRepositoryProvider).getById(timerId);
      if (timer != null) {
        _creating = false;
        _isTimer = true;
        _editTimerId = timer.id;
        _title.text = timer.title;
        _tHour = timer.durationSec ~/ 3600;
        _tMin = (timer.durationSec % 3600) ~/ 60;
        _tSec = timer.durationSec % 60;
        return;
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// Sound and vibration are global Settings choices; stored per-alarm ids
  /// are kept in Hive for schema stability but never authored here.
  Alarm _draftAlarm(String id) {
    final settings = ref.read(settingsControllerProvider);
    return Alarm(
      id: id,
      title: _title.text.trim(),
      isUtc: true,
      hour: _hour,
      minute: _minute,
      year: _date.year,
      month: _date.month,
      day: _date.day,
      repeat: AlarmRepeat.oneTime,
      days: List<bool>.filled(7, false),
      enabled: true,
      soundId: settings.defaultSoundId,
      vibId: settings.defaultVibId,
      createdAtUtc: DateTime.now().toUtc(),
    );
  }

  Future<void> _refreshArmed() async {
    try {
      await ref.read(schedulerProvider).refreshArmed(
            alarms: ref.read(alarmRepositoryProvider).all(),
            timers: ref.read(timerRepositoryProvider).all(),
            now: DateTime.now().toUtc(),
          );
    } catch (_) {
      // Status-only; the fire schedule is already synced.
    }
  }

  Future<void> _saveAlarm() async {
    final repo = ref.read(alarmRepositoryProvider);
    final existing = _editAlarmId != null ? repo.getById(_editAlarmId!) : null;
    final alarm = _draftAlarm(existing?.id ?? _uuid.v4());
    if (existing != null) {
      // Preserve identity fields the form doesn't edit.
      alarm
        ..enabled = existing.enabled
        ..createdAtUtc = existing.createdAtUtc;
    }
    await repo.upsert(alarm);
    final permissionsOk = await NotificationService.ensureFirePermissions();
    SyncOutcome outcome = SyncOutcome.cancelled;
    var schedulingOk = true;
    try {
      outcome = await ref
          .read(schedulerProvider)
          .syncAlarm(
            alarm,
            ref.read(settingsControllerProvider),
            now: DateTime.now().toUtc(),
          );
    } catch (_) {
      schedulingOk = false;
    }
    await _refreshArmed();
    if (!mounted) return;
    if (!permissionsOk || !schedulingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved, but notifications or exact alarms are off. '
            'Allow them to fire on time.',
          ),
        ),
      );
    } else if (outcome == SyncOutcome.expired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved, but that time already passed')),
      );
    }
    Navigator.pop(context);
  }

  Future<void> _saveTimer() async {
    final total = _tHour * 3600 + _tMin * 60 + _tSec;
    if (total <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Set a duration first')));
      return;
    }
    final repo = ref.read(timerRepositoryProvider);
    final title = _title.text.trim().isEmpty ? 'Timer' : _title.text.trim();
    final now = DateTime.now().toUtc();
    LarmTimer? timer;
    if (_editTimerId != null && repo.getById(_editTimerId!) != null) {
      timer = repo.getById(_editTimerId!);
      timer!
        ..title = title
        ..durationSec = total
        ..remainingSec = total
        ..status = TimerStatus.idle
        ..targetUtc = null
        ..enabled = true;
      await repo.upsert(timer);
      timer = await repo.start(timer.id, now);
    } else {
      final created = LarmTimer(
        id: _uuid.v4(),
        title: title,
        durationSec: total,
        remainingSec: total,
        status: TimerStatus.idle,
        enabled: true,
      );
      await repo.upsert(created);
      timer = await repo.start(created.id, now);
    }
    final permissionsOk = await NotificationService.ensureFirePermissions();
    var schedulingOk = true;
    if (timer != null) {
      try {
        await ref
            .read(schedulerProvider)
            .syncTimer(timer, ref.read(settingsControllerProvider), now: now);
      } catch (_) {
        schedulingOk = false;
      }
    }
    await _refreshArmed();
    if (!mounted) return;
    if (!permissionsOk || !schedulingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Timer saved, but notifications or exact alarms are off. '
            'Allow them to fire on time.',
          ),
        ),
      );
    }
    Navigator.pop(context);
  }

  Future<void> _deleteExisting() async {
    if (_editAlarmId != null) {
      final alarm = ref.read(alarmRepositoryProvider).getById(_editAlarmId!);
      await ref.read(alarmRepositoryProvider).delete(_editAlarmId!);
      if (alarm != null) {
        try {
          await ref
              .read(schedulerProvider)
              .syncAlarm(
                alarm..enabled = false,
                ref.read(settingsControllerProvider),
                now: DateTime.now().toUtc(),
              );
        } catch (_) {
          // Persistence already done.
        }
      }
    } else if (_editTimerId != null) {
      final timer = ref.read(timerRepositoryProvider).getById(_editTimerId!);
      await ref.read(timerRepositoryProvider).delete(_editTimerId!);
      if (timer != null) {
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
          // Persistence already done.
        }
      }
    }
    await _refreshArmed();
    if (!mounted) return;
    Navigator.pop(context);
  }

  String _previewText() {
    final draft = _draftAlarm('preview');
    final next = nextOccurrence(draft, fromUtc: DateTime.now().toUtc());
    if (next == null) return 'Already passed — pick another time';
    final date = DateFormat('EEE, MMM d').format(next.toUtc());
    return 'Fires $date · ${fmtTime(next)} UTC';
  }

  @override
  Widget build(BuildContext context) {
    final title = _creating
        ? (_isTimer ? 'New timer' : 'New alarm')
        : (_isTimer ? 'Edit timer' : 'Edit alarm');
    return Scaffold(
      backgroundColor: LarmPalette.backgroundDeep,
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!_creating)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(LucideIcons.trash2, color: LarmPalette.coral),
              onPressed: _deleteExisting,
            ),
        ],
      ),
      body: ListView(
        key: const ValueKey('editor-list'),
        padding: const EdgeInsets.all(12),
        children: [
          if (_creating) ...[
            SegmentedButton<_Kind>(
              segments: const [
                ButtonSegment(value: _Kind.alarm, label: Text('Alarm')),
                ButtonSegment(value: _Kind.timer, label: Text('Timer')),
              ],
              selected: {_isTimer ? _Kind.timer : _Kind.alarm},
              onSelectionChanged: (selected) async {
                await hapticTap();
                setState(() => _isTimer = selected.first == _Kind.timer);
              },
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _title,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _isTimer ? 'Timer title' : 'Alarm title',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          if (!_isTimer) ..._alarmForm(context),
          if (_isTimer) ..._timerForm(),
          const SizedBox(height: 10),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              textStyle: Theme.of(context).textTheme.titleMedium,
            ),
            onPressed: () async {
              await hapticConfirm();
              if (_isTimer) {
                await _saveTimer();
              } else {
                await _saveAlarm();
              }
            },
            child: Text(_isTimer ? 'Start timer' : 'Save alarm'),
          ),
        ),
      ),
    );
  }

  List<Widget> _alarmForm(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previewTime = DateTime.utc(
      _date.year,
      _date.month,
      _date.day,
      _hour,
      _minute,
    );

    return [
      // Time first, directly below the title. Both wheels wrap: 23 → 00 and
      // 59 → 00, with a larger font so values are easy to read and pick.
      _sectionLabel(context, 'Time'),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          WheelPicker<int>(
            key: const ValueKey('hour-wheel'),
            items: List<int>.generate(24, (i) => i),
            initialIndex: _hour,
            onSelected: (i) => setState(() => _hour = i),
            label: twoDigits,
            width: 92,
            loop: true,
          ),
          Text(':', style: Theme.of(context).textTheme.headlineLarge),
          WheelPicker<int>(
            key: const ValueKey('minute-wheel'),
            items: List<int>.generate(60, (i) => i),
            initialIndex: _minute,
            onSelected: (i) => setState(() => _minute = i),
            label: twoDigits,
            width: 92,
            loop: true,
          ),
        ],
      ),
      _sectionLabel(context, 'Date'),
      UtcDatePicker(
        selected: _date,
        onChanged: (date) => setState(() => _date = date),
      ),
      _sectionLabel(context, 'Time zone'),
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text(
          'This alarm fires at the UTC instant wherever you travel.',
          style: TextStyle(color: LarmPalette.muted, fontSize: 12),
        ),
      ),
      GlassCard(
        padding: const EdgeInsets.all(10),
        accent: LarmPalette.cyan,
        glow: true,
        child: Row(
          children: [
            CustomPaint(
              size: const Size.square(56),
              painter: AnalogPainter(
                now: previewTime,
                tickColor: scheme.onSurface,
                handColor: LarmPalette.violet,
                secondColor: LarmPalette.mint,
                ringColor: LarmPalette.cyan,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _previewText(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _timerForm() {
    return [
      _sectionLabel(context, 'Duration'),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          WheelPicker<int>(
            key: const ValueKey('dur-hour-wheel'),
            items: List<int>.generate(24, (i) => i),
            initialIndex: _tHour.clamp(0, 23),
            onSelected: (i) => setState(() => _tHour = i),
            label: (v) => '${twoDigits(v)}h',
            width: 88,
          ),
          WheelPicker<int>(
            key: const ValueKey('dur-minute-wheel'),
            items: List<int>.generate(60, (i) => i),
            initialIndex: _tMin.clamp(0, 59),
            onSelected: (i) => setState(() => _tMin = i),
            label: (v) => '${twoDigits(v)}m',
            width: 88,
          ),
          WheelPicker<int>(
            key: const ValueKey('dur-second-wheel'),
            items: List<int>.generate(60, (i) => i),
            initialIndex: _tSec.clamp(0, 59),
            onSelected: (i) => setState(() => _tSec = i),
            label: (v) => '${twoDigits(v)}s',
            width: 88,
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Timers start immediately and fire even if the app is killed.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
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
}
