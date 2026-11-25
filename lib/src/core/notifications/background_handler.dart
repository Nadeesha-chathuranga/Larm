import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'fire_handoff.dart';

/// Background notification tap/action handler.
///
/// Runs in a separate isolate when the app was terminated: keep it top-level,
/// dependency-free (no Riverpod, no Hive boxes, no BuildContext). It only
/// parses the payload/action and routes to the trigger page, which performs
/// stop/snooze through providers once the app is foregrounded.
///
/// Simultaneous fires queue as sequential `/trigger` routes (M5 queue
/// decision): each fire is handed off; dismissing the top reveals the next.
/// `enqueue` survives a cold full-screen-intent launch, where the navigator
/// does not exist yet when this callback runs.
@pragma('vm:entry-point')
void onBgAction(NotificationResponse response) {
  final fire = parseFirePayload(response.payload);
  if (fire == null) return;
  String? auto;
  final action = parseAlarmAction(response.actionId);
  if (action != null && (action.kind == 'stop' || action.kind == 'snooze')) {
    auto = action.kind;
  }
  unawaited(
    FireHandoff.enqueue(
      kind: fire.kind,
      id: fire.id,
      autoAction: auto,
    ),
  );
}

/// Parses tap payloads of the form `alarm:<id>` / `timer:<id>`.
({String kind, String id})? parseFirePayload(String? payload) {
  if (payload == null) return null;
  final sep = payload.indexOf(':');
  if (sep <= 0 || sep == payload.length - 1) return null;
  final kind = payload.substring(0, sep);
  if (kind != 'alarm' && kind != 'timer') return null;
  return (kind: kind, id: payload.substring(sep + 1));
}

/// Parses action IDs of the form `stop_<entryId>` / `snooze_<entryId>`.
({String kind, String id})? parseAlarmAction(String? actionId) {
  if (actionId == null) return null;
  final sep = actionId.indexOf('_');
  if (sep <= 0 || sep == actionId.length - 1) return null;
  final kind = actionId.substring(0, sep);
  if (kind != 'stop' && kind != 'snooze') return null;
  return (kind: kind, id: actionId.substring(sep + 1));
}
