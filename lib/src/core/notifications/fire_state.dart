import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prefs.dart';

/// Persisted snooze metadata for one alarm/timer.
///
/// Kept in SharedPreferences rather than Hive so no adapter/schema migration is
/// needed. The native ring-end receiver and the minute countdown ticker read
/// the same Flutter SharedPreferences file.
class SnoozeInfo {
  const SnoozeInfo({
    required this.kind,
    required this.id,
    required this.untilUtc,
    required this.remaining,
  });

  final String kind;
  final String id;
  final DateTime untilUtc;
  final int remaining;

  String get key => '$kind:$id';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'id': id,
    'until': untilUtc.toUtc().millisecondsSinceEpoch,
    'remaining': remaining,
  };

  String encode() => jsonEncode(toJson());

  static SnoozeInfo? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final kind = map['kind'] as String?;
      final id = map['id'] as String?;
      final until = map['until'];
      final remaining = map['remaining'];
      if (kind == null || (kind != 'alarm' && kind != 'timer')) return null;
      if (id == null || id.isEmpty) return null;
      if (until is! int || remaining is! int) return null;
      return SnoozeInfo(
        kind: kind,
        id: id,
        untilUtc: DateTime.fromMillisecondsSinceEpoch(until, isUtc: true),
        remaining: remaining,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Persisted snapshot of the closest armed fire, used by the native ticker.
class ArmedSnapshot {
  const ArmedSnapshot({required this.whenUtc, required this.label});

  final DateTime whenUtc;
  final String label;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'at': whenUtc.toUtc().millisecondsSinceEpoch,
    'label': label,
  };

  String encode() => jsonEncode(toJson());

  static ArmedSnapshot? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final at = map['at'];
      final label = map['label'] as String?;
      if (at is! int || label == null || label.isEmpty) return null;
      return ArmedSnapshot(
        whenUtc: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
        label: label,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Minute-granular countdown text shared by Dart and the native ticker.
/// The native ticker cannot refresh every second without waking the app, so
/// both sides use the same coarse wording (including the sub-minute case).
String armedCountdownLabel(Duration remaining) {
  if (remaining.isNegative || remaining.inSeconds <= 0) return 'now';
  if (remaining.inSeconds < 60) return 'in <1m';
  if (remaining.inHours > 0) {
    return 'in ${remaining.inHours}h ${remaining.inMinutes % 60}m';
  }
  return 'in ${remaining.inMinutes}m';
}

/// Short remaining-snooze text for tiles and the shade label.
String snoozeRemainingLabel(int remaining) =>
    remaining > 0 ? 'Snoozed · $remaining left' : 'Snoozed · last one';

Future<Map<String, SnoozeInfo>> readSnoozes() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(snoozedFiresKey);
    if (raw == null || raw.isEmpty) return <String, SnoozeInfo>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return <String, SnoozeInfo>{};
    final infos = <String, SnoozeInfo>{};
    for (final value in decoded.values) {
      if (value is! String) continue;
      final info = SnoozeInfo.decode(value);
      if (info != null) infos[info.key] = info;
    }
    return infos;
  } catch (_) {
    return <String, SnoozeInfo>{};
  }
}

Future<void> writeSnoozes(Map<String, SnoozeInfo> infos) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (infos.isEmpty) {
      await prefs.remove(snoozedFiresKey);
    } else {
      await prefs.setString(
        snoozedFiresKey,
        jsonEncode(infos.map(
          (key, info) => MapEntry<String, String>(key, info.encode()),
        )),
      );
    }
  } catch (_) {
    // Best effort; the in-memory store still covers this process.
  }
}

Future<ArmedSnapshot?> readArmedSnapshot() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(armedSnapshotKey);
    if (raw == null || raw.isEmpty) return null;
    return ArmedSnapshot.decode(raw);
  } catch (_) {
    return null;
  }
}

Future<void> writeArmedSnapshot(ArmedSnapshot? snapshot) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (snapshot == null) {
      await prefs.remove(armedSnapshotKey);
    } else {
      await prefs.setString(armedSnapshotKey, snapshot.encode());
    }
  } catch (_) {
    // Best effort.
  }
}

/// Riverpod view of the snooze metadata so tiles and the trigger page rebuild
/// immediately when a snooze is scheduled or cleared.
final snoozeStoreProvider =
    StateNotifierProvider<SnoozeStore, Map<String, SnoozeInfo>>(
  (_) => SnoozeStore(),
);

class SnoozeStore extends StateNotifier<Map<String, SnoozeInfo>> {
  /// [initial] is supplied by `main()` from SharedPreferences so a locked cold
  /// start can read the remaining snooze count before the dashboard loads.
  SnoozeStore([super.initial = const <String, SnoozeInfo>{}]);

  Future<void> load() async => state = await readSnoozes();

  Future<void> set(SnoozeInfo info) async {
    final next = Map<String, SnoozeInfo>.from(state)..[info.key] = info;
    state = next;
    await writeSnoozes(next);
  }

  Future<void> remove(String kind, String id) async {
    final next = Map<String, SnoozeInfo>.from(state)..remove('$kind:$id');
    state = next;
    await writeSnoozes(next);
  }

  /// Drops snoozes whose entry was deleted or whose fire instant has passed.
  Future<void> prune({
    required Set<String> aliveKeys,
    required DateTime now,
  }) async {
    final next = Map<String, SnoozeInfo>.from(state)
      ..removeWhere(
        (key, info) =>
            !aliveKeys.contains(key) || !info.untilUtc.isAfter(now.toUtc()),
      );
    if (next.length == state.length &&
        next.entries.every((entry) {
          final old = state[entry.key];
          return old != null &&
              old.id == entry.value.id &&
              old.kind == entry.value.kind &&
              old.untilUtc == entry.value.untilUtc &&
              old.remaining == entry.value.remaining;
        })) {
      return;
    }
    state = next;
    await writeSnoozes(next);
  }
}
