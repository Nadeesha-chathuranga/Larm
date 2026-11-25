import 'package:flutter_test/flutter_test.dart';
import 'package:larm/src/core/notifications/fire_handoff.dart';
import 'package:larm/src/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Clear any queue left by a previous test so each case starts fresh.
    await FireHandoff.drain((_) async => true);
  });

  test('pending fire encodes, decodes and builds route arguments', () {
    const fire = PendingFire(kind: 'alarm', id: 'a1', autoAction: 'snooze');
    final decoded = PendingFire.decode(fire.encode());

    expect(decoded, isNotNull);
    expect(decoded!.kind, 'alarm');
    expect(decoded.id, 'a1');
    expect(decoded.autoAction, 'snooze');
    expect(
      decoded.arguments,
      <String, Object?>{'alarmId': 'a1', 'autoAction': 'snooze'},
    );

    expect(PendingFire.decode('not json'), isNull);
    expect(PendingFire.decode('{"kind":"wat","id":"x"}'), isNull);
    expect(PendingFire.decode('{"kind":"alarm"}'), isNull);
  });

  test('enqueue dedupes tap and FSI callbacks for the same fire', () async {
    await FireHandoff.enqueue(kind: 'timer', id: 't1');
    await FireHandoff.enqueue(kind: 'timer', id: 't1');

    final pushed = <PendingFire>[];
    final count = await FireHandoff.drain((fire) async {
      pushed.add(fire);
      return true;
    });

    expect(count, 1);
    expect(pushed, hasLength(1));
    expect(pushed.single.arguments['timerId'], 't1');
  });

  test('takeInitial consumes one fire for the first route', () async {
    await FireHandoff.enqueue(kind: 'alarm', id: 'cold');
    await FireHandoff.enqueue(kind: 'timer', id: 'stacked');

    final initial = await FireHandoff.takeInitial();
    expect(initial?.kind, 'alarm');
    expect(initial?.id, 'cold');

    // The startup route must not be pushed again by the normal drain, while
    // a simultaneous fire still queues normally.
    final pushed = <PendingFire>[];
    expect(
      await FireHandoff.drain((fire) async {
        pushed.add(fire);
        return true;
      }),
      1,
    );
    expect(pushed.single.id, 'stacked');
  });

  test('takes a fire written by the native locked-screen bridge', () async {
    // FireLauncher.kt writes the same JSON/PendingIntent shape into Flutter's
    // SharedPreferences file when the companion FSI resumes MainActivity.
    SharedPreferences.setMockInitialValues(<String, Object>{
      pendingFiresKey: <String>[
        '{"kind":"timer","id":"native_fire"}',
        '{"kind":"alarm","id":"native_fire_two"}',
      ],
    });

    final initial = await FireHandoff.takeInitial();
    expect(initial?.kind, 'timer');
    expect(initial?.id, 'native_fire');

    // The startup route consumes its fire, but a second queued fire must wait
    // for the normal drain instead of being lost with the prefs rewrite.
    final pushed = <PendingFire>[];
    expect(
      await FireHandoff.drain((fire) async {
        pushed.add(fire);
        return true;
      }),
      1,
    );
    expect(pushed.single.id, 'native_fire_two');
  });

  test('explicit notification action wins over a plain launch', () async {
    await FireHandoff.enqueue(kind: 'alarm', id: 'a2');
    await FireHandoff.enqueue(kind: 'alarm', id: 'a2', autoAction: 'stop');

    final pushed = <PendingFire>[];
    await FireHandoff.drain((fire) async {
      pushed.add(fire);
      return true;
    });

    expect(pushed, hasLength(1));
    expect(pushed.single.autoAction, 'stop');
  });

  test('failed push stays queued for the next drain', () async {
    await FireHandoff.enqueue(kind: 'alarm', id: 'a3');
    var attempts = 0;

    final first = await FireHandoff.drain((_) async {
      attempts++;
      return false;
    });
    expect(first, 0);

    final second = await FireHandoff.drain((fire) async {
      attempts++;
      expect(fire.id, 'a3');
      return true;
    });
    expect(second, 1);
    expect(attempts, 2);
  });

  test('late duplicate callback does not push a second route', () async {
    await FireHandoff.enqueue(kind: 'alarm', id: 'a5');
    expect(await FireHandoff.drain((_) async => true), 1);

    await FireHandoff.enqueue(kind: 'alarm', id: 'a5');
    final pushed = <PendingFire>[];
    final count = await FireHandoff.drain((fire) async {
      pushed.add(fire);
      return true;
    });

    expect(count, 0);
    expect(pushed, isEmpty);
  });

  test('late notification action reaches the open page without a route', () async {
    await FireHandoff.enqueue(kind: 'timer', id: 't2');
    await FireHandoff.drain((_) async => true);

    final received = FireHandoff.liveActions.first;
    await FireHandoff.enqueue(
      kind: 'timer',
      id: 't2',
      autoAction: 'snooze',
    );

    final drained = FireHandoff.drain((_) async => true);
    expect((await received).autoAction, 'snooze');
    expect(await drained, 0);
  });

  test('enqueue requests the installed drain callback', () async {
    var requests = 0;
    FireHandoff.setDrainCallback(() => requests++);
    addTearDown(() => FireHandoff.clearDrainCallback());

    await FireHandoff.enqueue(kind: 'alarm', id: 'a4');

    expect(requests, 1);
  });
}
