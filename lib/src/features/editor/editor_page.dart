import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:vibration/vibration.dart';

import '../../core/audio/sounds.dart';
import '../../core/haptics.dart';
import '../../core/notifications/scheduler.dart';
import '../../core/time/clock.dart';
import '../../data/models/alarm.dart';
import '../../data/models/larm_timer.dart';
import '../../data/models/settings.dart';
import '../../data/repos/alarm_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/repos/timer_repo.dart';
import '../dashboard/widgets/analog_painter.dart';
import 'widgets/sound_sheet.dart';
import 'widgets/wheel_picker.dart';

enum _Kind { alarm, timer }

const _dayShort = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _dayFull = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];

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
  bool _isUtc = false;
  int _hour = 8;
  int _minute = 0;
  DateTime _date = DateTime.now();
  int _repeat = AlarmRepeat.daily;
  List<bool> _days = List<bool>.filled(7, false);
  String _soundId = 'glass_chime';
  String _vibId = 'short';

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

    final settings = ref.read(settingsControllerProvider);
    if (isKnownSound(settings.defaultSoundId)) {
      _soundId = settings.defaultSoundId;
    }
    final now = DateTime.now();
    _hour = (now.hour + 1) % 24;
    _minute = 0;
    _date = DateTime(now.year, now.month, now.day);

    if (alarmId != null) {
      final alarm = ref.read(alarmRepositoryProvider).getById(alarmId);
      if (alarm != null) {
        _creating = false;
        _isTimer = false;
        _editAlarmId = alarm.id;
        _title.text = alarm.title;
        _isUtc = alarm.isUtc;
        _hour = alarm.hour;
        _minute = alarm.minute;
        if (alarm.year != null && alarm.month != null && alarm.day != null) {
          _date = DateTime(alarm.year!, alarm.month!, alarm.day!);
        }
        _repeat = alarm.repeat;
        _days = List<bool>.from(
            alarm.days.length == 7 ? alarm.days : List.filled(7, false));
        if (isKnownSound(alarm.soundId)) _soundId = alarm.soundId;
        if (vibrationPatterns.any((p) => p.id == alarm.vibId)) {
          _vibId = alarm.vibId;
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

  Alarm _draftAlarm(String id) {
    return Alarm(
      id: id,
      title: _title.text.trim(),
      isUtc: _isUtc,
      hour: _hour,
      minute: _minute,
      year: _repeat == AlarmRepeat.oneTime ? _date.year : null,
      month: _repeat == AlarmRepeat.oneTime ? _date.month : null,
      day: _repeat == AlarmRepeat.oneTime ? _date.day : null,
      repeat: _repeat,
      days: List<bool>.from(_days),
      enabled: true,
      soundId: _soundId,
      vibId: _vibId,
      createdAtUtc: DateTime.now().toUtc(),
    );
  }

  Future<void> _saveAlarm() async {
    if (_repeat == AlarmRepeat.custom && _days.every((d) => !d)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one day')),
      );
      return;
    }
    final repo = ref.read(alarmRepositoryProvider);
    final existing =
        _editAlarmId != null ? repo.getById(_editAlarmId!) : null;
    final alarm = _draftAlarm(existing?.id ?? _uuid.v4());
    if (existing != null) {
      // Preserve identity fields the form doesn't edit.
      alarm
        ..enabled = existing.enabled
        ..createdAtUtc = existing.createdAtUtc;
    }
    await repo.upsert(alarm);
    SyncOutcome outcome = SyncOutcome.cancelled;
    try {
      outcome = await ref.read(schedulerProvider).syncAlarm(
            alarm,
            ref.read(settingsControllerProvider),
            now: DateTime.now(),
          );
    } catch (_) {
      // Platform channels absent (tests/desktop): persistence already done.
    }
    if (!mounted) return;
    if (outcome == SyncOutcome.expired) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a duration first')),
      );
      return;
    }
    final repo = ref.read(timerRepositoryProvider);
    final title = _title.text.trim().isEmpty ? 'Timer' : _title.text.trim();
    final now = DateTime.now();
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
    if (timer != null) {
      try {
        await ref.read(schedulerProvider).syncTimer(
              timer,
              ref.read(settingsControllerProvider),
              now: now,
            );
      } catch (_) {
        // Persistence already done; scheduling is best effort here.
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _deleteExisting() async {
    if (_editAlarmId != null) {
      final alarm =
          ref.read(alarmRepositoryProvider).getById(_editAlarmId!);
      await ref.read(alarmRepositoryProvider).delete(_editAlarmId!);
      if (alarm != null) {
        try {
          await ref.read(schedulerProvider).syncAlarm(
                alarm..enabled = false,
                ref.read(settingsControllerProvider),
                now: DateTime.now(),
              );
        } catch (_) {
          // Persistence already done.
        }
      }
    } else if (_editTimerId != null) {
      final timer =
          ref.read(timerRepositoryProvider).getById(_editTimerId!);
      await ref.read(timerRepositoryProvider).delete(_editTimerId!);
      if (timer != null) {
        try {
          await ref.read(schedulerProvider).syncTimer(
                timer
                  ..status = TimerStatus.idle
                  ..targetUtc = null,
                ref.read(settingsControllerProvider),
                now: DateTime.now(),
              );
        } catch (_) {
          // Persistence already done.
        }
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _previewVibration() async {
    final pattern = vibrationById(_vibId);
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

  String _previewText(Settings settings) {
    final draft = _draftAlarm('preview');
    final next = nextOccurrence(draft, fromLocal: DateTime.now());
    if (next == null) return 'Already passed — pick another time';
    final use24h = settings.timeFormat == 1;
    final date = DateFormat('EEE, MMM d').format(next);
    final main = '$date · ${fmtTime(next, use24h: use24h)}';
    final equiv = _isUtc
        ? 'Local ${fmtTime(next.toLocal(), use24h: use24h)}'
        : 'UTC ${fmtTime(next.toUtc(), use24h: use24h)}';
    return 'Fires $main ($equiv)';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final title = _creating
        ? (_isTimer ? 'New timer' : 'New alarm')
        : (_isTimer ? 'Edit timer' : 'Edit alarm');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!_creating)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteExisting,
            ),
        ],
      ),
      body: ListView(
        key: const ValueKey('editor-list'),
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 16),
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
          const SizedBox(height: 8),
          if (!_isTimer) ..._alarmForm(context, settings),
          if (_isTimer) ..._timerForm(),
          const SizedBox(height: 16),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
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

  List<Widget> _alarmForm(BuildContext context, Settings settings) {
    final scheme = Theme.of(context).colorScheme;
    final dateItems = List<DateTime>.generate(
      90,
      (i) {
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day + i);
      },
    );
    var dateIndex = dateItems.indexWhere(
      (d) => d.year == _date.year && d.month == _date.month && d.day == _date.day,
    );
    if (dateIndex < 0) dateIndex = 0;
    final previewTime = _isUtc
        ? DateTime.utc(_date.year, _date.month, _date.day, _hour, _minute)
            .toLocal()
        : DateTime(_date.year, _date.month, _date.day, _hour, _minute);

    return [
      _sectionLabel(context, 'Time zone'),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Local')),
          ButtonSegment(value: true, label: Text('UTC')),
        ],
        selected: {_isUtc},
        onSelectionChanged: (selected) async {
          await hapticTap();
          setState(() => _isUtc = selected.first);
        },
      ),
      const SizedBox(height: 4),
      Text(
        _isUtc
            ? 'Fires at the UTC instant wherever you travel — for cross-region groups.'
            : 'Follows the device timezone, DST included.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CustomPaint(
                size: const Size.square(72),
                painter: AnalogPainter(
                  now: previewTime,
                  tickColor: scheme.onSurface,
                  handColor: scheme.primary,
                  secondColor: scheme.primary,
                  ringColor: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(_previewText(settings))),
            ],
          ),
        ),
      ),
      _sectionLabel(context, 'Time'),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_repeat == AlarmRepeat.oneTime)
            WheelPicker<DateTime>(
              key: const ValueKey('date-wheel'),
              items: dateItems,
              initialIndex: dateIndex,
              onSelected: (i) => setState(() => _date = dateItems[i]),
              label: (d) => DateFormat('EEE d').format(d),
              width: 104,
            ),
          WheelPicker<int>(
            key: const ValueKey('hour-wheel'),
            items: List<int>.generate(24, (i) => i),
            initialIndex: _hour,
            onSelected: (i) => setState(() => _hour = i),
            label: twoDigits,
            width: 72,
          ),
          Text(':', style: Theme.of(context).textTheme.headlineMedium),
          WheelPicker<int>(
            key: const ValueKey('minute-wheel'),
            items: List<int>.generate(60, (i) => i),
            initialIndex: _minute,
            onSelected: (i) => setState(() => _minute = i),
            label: twoDigits,
            width: 72,
          ),
        ],
      ),
      _sectionLabel(context, 'Repeat'),
      Wrap(
        spacing: 8,
        children: [
          _repeatChip('One-time', AlarmRepeat.oneTime),
          _repeatChip('Daily', AlarmRepeat.daily),
          _repeatChip('Weekdays', AlarmRepeat.weekdays),
          _repeatChip('Custom', AlarmRepeat.custom),
        ],
      ),
      if (_repeat == AlarmRepeat.custom) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List<Widget>.generate(7, (i) {
            final selected = _days[i];
            return FilterChip(
              label: Text(_dayShort[i]),
              tooltip: _dayFull[i],
              selected: selected,
              onSelected: (next) async {
                await hapticTap();
                setState(() => _days[i] = next);
              },
            );
          }),
        ),
      ],
      _sectionLabel(context, 'Sound'),
      Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          title: Text(
            _soundLabel(_soundId),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            _soundCategory(_soundId),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await hapticTap();
            if (!context.mounted) return;
            final picked =
                await showSoundPickerSheet(context, currentId: _soundId);
            if (picked != null && mounted) {
              setState(() => _soundId = picked);
            }
          },
        ),
      ),
      _sectionLabel(context, 'Vibration'),
      Wrap(
        spacing: 8,
        children: [
          for (final p in vibrationPatterns)
            ChoiceChip(
              label: Text(p.label),
              selected: _vibId == p.id,
              onSelected: (selected) async {
                if (!selected) return;
                await hapticTap();
                setState(() => _vibId = p.id);
                await _previewVibration();
              },
            ),
        ],
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
      padding: const EdgeInsets.only(top: 20, bottom: 8),
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

String _soundLabel(String id) => soundLabel(id);

String _soundCategory(String id) => soundCategory(id);

  Widget _repeatChip(String label, int value) {
    return ChoiceChip(
      label: Text(label),
      selected: _repeat == value,
      onSelected: (selected) async {
        if (!selected) return;
        await hapticTap();
        setState(() => _repeat = value);
      },
    );
  }
}
