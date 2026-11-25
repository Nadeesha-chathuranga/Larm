import 'dart:typed_data';

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
const String larmArmedV2 = 'larm_armed_v2';
const String larmRangV2 = 'larm_rang_v2';

/// Bundled tones are 2.4–4s. `FLAG_INSISTENT` (4) makes Android repeat the
/// channel sound until the notification is cancelled; `timeoutAfter` closes
/// that ring window after the configured duration (default ~10s). A silent
/// summary replaces it so the user can still see that the alarm went off.
const int alarmRingMs = 10 * 1000;
const int insistentNotificationFlag = 4; // Notification.FLAG_INSISTENT

/// Dedicated id for the silent "alarm rang at …" notice posted when the ring
/// window closes. Kept apart from fire ids so the summary survives until tap.
const int rangNotificationId = 0x52414E47;

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
        larmArmedV2,
        'Alarm status',
        description: 'Silent ongoing notice showing the next armed alarm.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
      const AndroidNotificationChannel(
        larmRangV2,
        'Alarm rang',
        description: 'Silent reminder that an alarm or timer went off.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
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

/// Action ID for the Cancel button on a ringing notification. The id keeps
/// its legacy `stop_` prefix so existing action routes stay stable.
String stopActionId(String entryId) => 'stop_$entryId';

/// Action ID for the Snooze button on a ringing notification.
String snoozeActionId(String entryId) => 'snooze_$entryId';

/// Full-screen alarm-style details for one fire.
///
/// [overrideMode] picks the DND-bypassing channel (requires notification
/// policy access, requested when the user opts into override).
/// [entryId] is the alarm/timer id, namespaced by [payload]. [vibrationId] is
/// the global pattern from Settings, applied to every alarm and timer.
AndroidNotificationDetails alarmDetails({
  required bool overrideMode,
  required String entryId,
  required String payload,
  required String soundId,
  required String vibrationId,
  int ringMs = alarmRingMs,
}) {
  final channelId =
      channelFor(overrideMode: overrideMode, soundId: soundId);
  final channelName =
      overrideMode ? 'Alarms (override)' : 'Alarms · $soundId';
  final vibration = vibrationById(vibrationId);
  final vibrationOff = vibration.id == 'off';
  final vibrationPattern = vibration.pattern.isEmpty
      ? Int64List.fromList([0, vibration.duration])
      : Int64List.fromList(vibration.pattern);
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
    enableVibration: !vibrationOff,
    vibrationPattern: vibrationOff ? null : vibrationPattern,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    timeoutAfter: ringMs,
    additionalFlags: Int32List.fromList(const [insistentNotificationFlag]),
    actions: [
      AndroidNotificationAction(
        snoozeActionId(entryId),
        'Snooze',
        showsUserInterface: true,
      ),
      AndroidNotificationAction(
        stopActionId(entryId),
        'Cancel',
        showsUserInterface: true,
      ),
    ],
  );
}

/// Silent, ongoing status notification. This makes an armed alarm visible in
/// the shade and survives the app being swiped away; it never sounds or steals
/// the lock screen.
AndroidNotificationDetails armedDetails() => const AndroidNotificationDetails(
      larmArmedV2,
      'Alarm status',
      channelDescription: 'Silent ongoing notice showing the next armed alarm.',
      importance: Importance.low,
      priority: Priority.low,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      channelShowBadge: false,
    );
