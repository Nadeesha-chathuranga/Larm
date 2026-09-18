import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/larm_timer.dart';

final timerBoxProvider =
    Provider<Box<LarmTimer>>((_) => throw UnimplementedError('Set in main()'));

final timerRepositoryProvider = Provider<TimerRepository>(
    (ref) => TimerRepository(ref.watch(timerBoxProvider)));

/// Timer persistence. Background completion scheduling lands in M2/M4.
class TimerRepository {
  TimerRepository(this._box);

  final Box<LarmTimer> _box;

  List<LarmTimer> all() => _box.values.toList();

  ValueListenable<Box<LarmTimer>> listenable() => _box.listenable();

  LarmTimer? getById(String id) => _box.get(id);

  Future<void> upsert(LarmTimer timer) => _box.put(timer.id, timer);

  Future<void> delete(String id) => _box.delete(id);

  /// Starts (or resumes) a timer: target = now + remaining.
  Future<LarmTimer?> start(String id, DateTime now) async {
    final timer = _box.get(id);
    if (timer == null) return null;
    final remaining =
        timer.status == TimerStatus.paused ? timer.remainingSec : timer.durationSec;
    timer
      ..remainingSec = remaining
      ..status = TimerStatus.running
      ..targetUtc = now.toUtc().add(Duration(seconds: remaining))
      ..enabled = true;
    await timer.save();
    return timer;
  }

  /// Pauses a running timer, freezing the remaining seconds.
  Future<LarmTimer?> pause(String id, DateTime now) async {
    final timer = _box.get(id);
    if (timer == null || timer.status != TimerStatus.running) return timer;
    final target = timer.targetUtc;
    timer
      ..remainingSec = target == null
          ? timer.remainingSec
          : target
              .toUtc()
              .difference(now.toUtc())
              .inSeconds
              .clamp(0, timer.durationSec)
      ..status = TimerStatus.paused
      ..targetUtc = null;
    await timer.save();
    return timer;
  }

  /// Resets to the full duration and idle state.
  Future<LarmTimer?> reset(String id) async {
    final timer = _box.get(id);
    if (timer == null) return null;
    timer
      ..remainingSec = timer.durationSec
      ..status = TimerStatus.idle
      ..targetUtc = null;
    await timer.save();
    return timer;
  }
}
