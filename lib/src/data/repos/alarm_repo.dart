import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/alarm.dart';

final alarmBoxProvider =
    Provider<Box<Alarm>>((_) => throw UnimplementedError('Set in main()'));

final alarmRepositoryProvider = Provider<AlarmRepository>(
    (ref) => AlarmRepository(ref.watch(alarmBoxProvider)));

/// Alarm persistence. Scheduling side-effects wire up in M2; M1 only persists.
class AlarmRepository {
  AlarmRepository(this._box);

  final Box<Alarm> _box;

  List<Alarm> all() {
    final items = _box.values.toList();
    items.sort((a, b) => a.createdAtUtc.compareTo(b.createdAtUtc));
    return items;
  }

  ValueListenable<Box<Alarm>> listenable() => _box.listenable();

  Alarm? getById(String id) => _box.get(id);

  Future<void> upsert(Alarm alarm) => _box.put(alarm.id, alarm);

  Future<void> delete(String id) => _box.delete(id);

  Future<void> toggle(String id, bool enabled) async {
    final alarm = _box.get(id);
    if (alarm == null) return;
    alarm.enabled = enabled;
    await alarm.save();
  }
}
