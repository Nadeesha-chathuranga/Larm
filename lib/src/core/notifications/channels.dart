import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/audio/sounds.dart';

/// M6 channel set (v1 ids `larm_follow` / `larm_override_v1` are deleted on
/// upgrade — channels are immutable, so tones ship as new channel ids).
///
/// Android routes sound per channel, not per notification, hence one follow
/// channel per bundled tone. Override mode is reliability-first: a single
/// bypass channel (tone sacrificed for guaranteed DND bypass).
const String larmFollowV2 = 'larm_follow_v2';
const String larmOverrideV2 = 'larm_override_v2';

String toneChannelId(String soundId) => 'larm_tone_${soundId}_v2';

/// Legacy v1 ids, deleted in [NotificationService.init].
const List<String> legacyChannelIds = ['larm_follow', 'larm_override_v1'];

/// Picks the channel for a fire: override mode always uses the bypass
/// channel; follow mode uses the tone channel (or the default channel for
/// `system`/unknown sounds).
String channelFor({required bool overrideMode, required String soundId}) {
  if (overrideMode) return larmOverrideV2;
  if (soundId != 'system' && isKnownSound(soundId)) {
    return toneChannelId(soundId);
  }
  return larmFollowV2;
}

/// Full set of v2 channels to create at startup.
List<AndroidNotificationChannel> v2Channels() => [
      const AndroidNotificationChannel(
        larmFollowV2,
        'Alarms',
        description: 'Alarm and timer alerts. Follows system sound mode.',
        importance: Importance.high,
      ),
      for (final sound in alarmSounds)
        if (sound.id != 'system')
          AndroidNotificationChannel(
            toneChannelId(sound.id),
            'Alarms · ${sound.label}',
            description:
                'Alarm and timer alerts with the ${sound.label} tone.',
            importance: Importance.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(sound.id),
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
      const AndroidNotificationChannel(
        larmOverrideV2,
        'Alarms (override)',
        description: 'Alarm and timer alerts that bypass Do Not Disturb.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        bypassDnd: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    ];

/// Notification tap payload for an alarm fire.
String alarmPayload(String alarmId) => 'alarm:$alarmId';

/// Notification tap payload for a timer completion.
String timerPayload(String timerId) => 'timer:$timerId';

/// Action ID for the Stop button on a ringing notification.
String stopActionId(String entryId) => 'stop_$entryId';

/// Action ID for the Snooze button on a ringing notification.
String snoozeActionId(String entryId) => 'snooze_$entryId';

/// Full-screen alarm-style details for one fire.
///
/// [overrideMode] picks the DND-bypassing channel (requires notification
/// policy access, requested when the user opts into override).
/// [entryId] is the alarm/timer id, namespaced by [payload].
AndroidNotificationDetails alarmDetails({
  required bool overrideMode,
  required String entryId,
  required String payload,
  required String soundId,
}) {
  final channelId =
      channelFor(overrideMode: overrideMode, soundId: soundId);
  final channelName =
      overrideMode ? 'Alarms (override)' : 'Alarms · $soundId';
  return AndroidNotificationDetails(
    channelId,
    channelName,
    importance: overrideMode ? Importance.max : Importance.high,
    priority: overrideMode ? Priority.max : Priority.high,
    channelBypassDnd: overrideMode,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    fullScreenIntent: true,
    ongoing: true,
    autoCancel: false,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    actions: [
      AndroidNotificationAction(
        snoozeActionId(entryId),
        'Snooze',
        showsUserInterface: true,
      ),
      AndroidNotificationAction(
        stopActionId(entryId),
        'Stop',
        showsUserInterface: true,
      ),
    ],
  );
}
