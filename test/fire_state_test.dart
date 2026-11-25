import 'package:flutter_test/flutter_test.dart';
import 'package:larm/src/core/notifications/fire_state.dart';
import 'package:larm/src/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('snooze info encodes and rejects malformed payloads', () {
    final info = SnoozeInfo(
      kind: 'alarm',
      id: 'a1',
      untilUtc: DateTime.utc(2026, 11, 25, 12, 35),
      remaining: 2,
    );
    final decoded = SnoozeInfo.decode(info.encode());
    expect(decoded, isNotNull);
    expect(decoded!.key, 'alarm:a1');
    expect(decoded.kind, 'alarm');
    expect(decoded.id, 'a1');
    expect(decoded.untilUtc, DateTime.utc(2026, 11, 25, 12, 35));
    expect(decoded.remaining, 2);

    expect(SnoozeInfo.decode('not json'), isNull);
    expect(
      SnoozeInfo.decode('{"kind":"timer","id":"","until":1,"remaining":1}'),
      isNull,
    );
    expect(
      SnoozeInfo.decode('{"kind":"other","id":"x","until":1,"remaining":1}'),
      isNull,
    );
  });

  test('snoozes persist through SharedPreferences', () async {
    final a = SnoozeInfo(
      kind: 'alarm',
      id: 'a1',
      untilUtc: DateTime.utc(2026, 11, 25, 12, 35),
      remaining: 1,
    );
    final t = SnoozeInfo(
      kind: 'timer',
      id: 't1',
      untilUtc: DateTime.utc(2026, 11, 25, 13, 0),
      remaining: 0,
    );
    await writeSnoozes(<String, SnoozeInfo>{a.key: a, t.key: t});
    final raw = (await SharedPreferences.getInstance()).getString(
      snoozedFiresKey,
    );
    expect(raw, isNotNull);

    final read = await readSnoozes();
    expect(read, hasLength(2));
    expect(read[a.key]?.remaining, 1);
    expect(read[t.key]?.untilUtc, DateTime.utc(2026, 11, 25, 13, 0));
  });

  test('armed snapshot round trips and countdown labels are minute-granular',
      () async {
    final snapshot = ArmedSnapshot(
      whenUtc: DateTime.utc(2026, 11, 25, 12, 35),
      label: 'Morning · 12:35 UTC',
    );
    await writeArmedSnapshot(snapshot);
    final read = await readArmedSnapshot();
    expect(read, isNotNull);
    expect(read!.whenUtc, snapshot.whenUtc);
    expect(read.label, snapshot.label);

    expect(armedCountdownLabel(const Duration(seconds: -1)), 'now');
    expect(armedCountdownLabel(const Duration(seconds: 45)), 'in <1m');
    expect(armedCountdownLabel(const Duration(minutes: 5, seconds: 20)),
        'in 5m');
    expect(
        armedCountdownLabel(const Duration(hours: 2, minutes: 7)), 'in 2h 7m');
    expect(snoozeRemainingLabel(2), 'Snoozed · 2 left');
    expect(snoozeRemainingLabel(0), 'Snoozed · last one');
  });

  test('prune drops deleted entries and snoozes whose instant passed', () async {
    final alive = SnoozeInfo(
      kind: 'alarm',
      id: 'a1',
      untilUtc: DateTime.utc(2026, 11, 25, 12, 35),
      remaining: 2,
    );
    final past = SnoozeInfo(
      kind: 'timer',
      id: 't1',
      untilUtc: DateTime.utc(2026, 11, 25, 12, 0),
      remaining: 1,
    );
    final deleted = SnoozeInfo(
      kind: 'alarm',
      id: 'gone',
      untilUtc: DateTime.utc(2026, 11, 25, 13, 0),
      remaining: 1,
    );
    await writeSnoozes(<String, SnoozeInfo>{
      alive.key: alive,
      past.key: past,
      deleted.key: deleted,
    });

    final store = SnoozeStore();
    await store.load();
    expect(store.state, hasLength(3));

    await store.prune(
      aliveKeys: <String>{alive.key, past.key},
      now: DateTime.utc(2026, 11, 25, 12, 30),
    );
    expect(store.state, hasLength(1));
    expect(store.state[alive.key], isNotNull);

    final persisted = await readSnoozes();
    expect(persisted, hasLength(1));
    expect(persisted[alive.key], isNotNull);
  });
}
