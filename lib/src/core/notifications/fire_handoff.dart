import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../prefs.dart';

/// Signature of the callback `LarmApp` installs to drain queued fires.
typedef DrainCallback = void Function();

/// A fire that still needs to open the ringing page.
///
/// Notification callbacks can run before `runApp()` has attached the
/// navigator, so a direct `pushNamed` is silently lost on cold full-screen
/// intent launches. Fires are queued here and drained once the navigator is
/// ready. SharedPreferences makes the queue survive the background isolate.
class PendingFire {
  const PendingFire({
    required this.kind,
    required this.id,
    this.autoAction,
  });

  /// `alarm` or `timer`.
  final String kind;

  /// The alarm/timer id carried by the notification payload.
  final String id;

  /// `stop` or `snooze` when the fire came from a notification action button.
  final String? autoAction;

  bool get isValid =>
      (kind == 'alarm' || kind == 'timer') && id.isNotEmpty;

  /// Arguments understood by the `/trigger` route in `app.dart`.
  Map<String, Object?> get arguments => <String, Object?>{
        '${kind}Id': id,
        if (autoAction != null) 'autoAction': autoAction,
      };

  String encode() => jsonEncode(<String, dynamic>{
        'kind': kind,
        'id': id,
        if (autoAction != null) 'autoAction': autoAction,
      });

  static PendingFire? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final kind = map['kind'] as String?;
      final id = map['id'] as String?;
      if (kind == null || (kind != 'alarm' && kind != 'timer')) return null;
      if (id == null || id.isEmpty) return null;
      final action = map['autoAction'] as String?;
      return PendingFire(
        kind: kind,
        id: id,
        autoAction: (action == 'stop' || action == 'snooze') ? action : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'PendingFire($kind:$id, auto=$autoAction)';
}

/// Queue of fires waiting to be shown as the full-screen ringing page.
class FireHandoff {
  FireHandoff._();

  static final List<PendingFire> _memory = <PendingFire>[];
  static bool _draining = false;
  static DrainCallback? _drainCallback;

  /// A late Stop/Snooze callback for a fire whose page is already open is
  /// delivered here instead of pushing a second ringing route.
  static final StreamController<PendingFire> _liveActions =
      StreamController<PendingFire>.broadcast();
  static Stream<PendingFire> get liveActions => _liveActions.stream;

  /// An FSI, a notification tap and the exact-alarm bridge can all report the
  /// same fire seconds apart. Keep this window longer than the OS handoff
  /// chain but shorter than a snooze, so a real later fire is never suppressed.
  static const Duration _dedupeWindow = Duration(seconds: 90);

  /// Installed by `LarmApp` so `enqueue` can ask the live app to drain now.
  static void setDrainCallback(DrainCallback callback) =>
      _drainCallback = callback;

  static void clearDrainCallback([DrainCallback? callback]) {
    if (callback == null || identical(_drainCallback, callback)) {
      _drainCallback = null;
    }
  }

  static void requestDrain() => _drainCallback?.call();

  /// Stores a fire. Duplicate taps/FSI launches for the same entry collapse
  /// into one; an explicit Stop/Snooze action wins over a plain launch.
  static Future<void> enqueue({
    required String kind,
    required String id,
    String? autoAction,
  }) async {
    final fire = PendingFire(kind: kind, id: id, autoAction: autoAction);
    if (!fire.isValid) return;
    // Plain duplicate launches are dropped here. Explicit actions still go
    // through so `drain` can hand them to an already-open TriggerPage.
    if (autoAction == null &&
        _isRecent(await _readRecent(), _fireKey(fire), DateTime.now())) {
      return;
    }
    _merge(_memory, fire);
    await _persist();
    requestDrain();
  }

  /// Removes one queued fire for app startup.
  ///
  /// A locked cold start must show the ringing page as the first route. The
  /// fire is marked recent so the normal drain cannot push a second copy.
  static Future<PendingFire?> takeInitial() async {
    final stored = await _read();
    final candidates = <PendingFire>[...stored, ..._memory];
    if (candidates.isEmpty) return null;
    final fire = candidates.first;
    bool same(PendingFire entry) =>
        entry.kind == fire.kind && entry.id == fire.id;
    _memory.removeWhere(same);
    final remaining = <PendingFire>[
      ...stored.where((entry) => !same(entry)),
      ..._memory,
    ];
    await _persistAll(remaining);
    await _markRecent([_fireKey(fire)]);
    return fire;
  }

  /// Pushes every queued fire through [push].
  ///
  /// Returns the number pushed. Fires whose push fails stay queued for the
  /// next attempt, so a callback firing before the navigator exists is safe.
  static Future<int> drain(Future<bool> Function(PendingFire fire) push) async {
    if (_draining) return 0;
    _draining = true;
    try {
      final stored = await _read();
      final recent = await _readRecent();
      final queue = <PendingFire>[];
      for (final fire in [...stored, ..._memory]) {
        if (_isRecent(recent, _fireKey(fire), DateTime.now())) {
          // The page for this fire is already open. A late action button must
          // still take effect, but it must not create a second route.
          if (fire.autoAction != null) _liveActions.add(fire);
          continue;
        }
        _merge(queue, fire);
      }
      if (queue.isEmpty) return 0;

      final remaining = <PendingFire>[];
      final shown = <String>[];
      var pushed = 0;
      for (final fire in queue) {
        bool ok;
        try {
          ok = await push(fire);
        } catch (_) {
          ok = false;
        }
        if (ok) {
          pushed++;
          shown.add(_fireKey(fire));
        } else {
          remaining.add(fire);
        }
      }
      if (shown.isNotEmpty) await _markRecent(shown);
      _memory
        ..clear()
        ..addAll(remaining);
      await _persist();
      return pushed;
    } finally {
      _draining = false;
    }
  }

  static Future<List<PendingFire>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(pendingFiresKey) ?? <String>[];
      return raw.map(PendingFire.decode).whereType<PendingFire>().toList();
    } catch (_) {
      return <PendingFire>[];
    }
  }

  static Future<void> _persist() => _persistAll(_memory);

  static Future<void> _persistAll(Iterable<PendingFire> fires) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = fires.map((fire) => fire.encode()).toList();
      if (encoded.isEmpty) {
        await prefs.remove(pendingFiresKey);
      } else {
        await prefs.setStringList(pendingFiresKey, encoded);
      }
    } catch (_) {
      // Method channel unavailable (e.g. a background isolate in a test);
      // the in-memory queue still covers the current process.
    }
  }

  static String _fireKey(PendingFire fire) => '${fire.kind}:${fire.id}';

  static bool _isRecent(
    Map<String, int> recent,
    String key,
    DateTime now,
  ) {
    final at = recent[key];
    if (at == null || at > now.millisecondsSinceEpoch) return false;
    return now.millisecondsSinceEpoch - at < _dedupeWindow.inMilliseconds;
  }

  static Future<Map<String, int>> _readRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(recentFiresKey);
      if (raw == null || raw.isEmpty) return <String, int>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, int>{};
      final now = DateTime.now().millisecondsSinceEpoch;
      return decoded.map(
        (key, value) => MapEntry<String, int>(key, value is int ? value : 0),
      )..removeWhere((key, value) => now - value >= _dedupeWindow.inMilliseconds);
    } catch (_) {
      return <String, int>{};
    }
  }

  static Future<void> _markRecent(Iterable<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recent = await _readRecent();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final key in keys) {
        recent[key] = now;
      }
      await prefs.setString(
        recentFiresKey,
        jsonEncode(recent),
      );
    } catch (_) {
      // Best effort: an in-memory queue still covers this process.
    }
  }

  static void _merge(List<PendingFire> list, PendingFire fire) {
    final index = list.indexWhere(
      (entry) => entry.kind == fire.kind && entry.id == fire.id,
    );
    if (index < 0) {
      list.add(fire);
      return;
    }
    if (list[index].autoAction == null && fire.autoAction != null) {
      list[index] = fire;
    }
  }
}
