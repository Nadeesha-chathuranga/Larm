import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/audio/sounds.dart';

/// Notification channel ids.
///
/// v1 (`larm_follow` / `larm_override_v1`) and v2 (one channel per tone) are
/// deleted on upgrade. Android channels are immutable, so v3 encodes the
/// selected tone and volume bucket in each channel id. Changing Settings
/// creates a fresh channel with a gain-scaled raw sound and removes the old
/// one, which makes the volume slider change the real scheduled alarm
/// loudness instead of only the in-app preview.
const String larmFollowV3 = 'larm_follow_v3';
const String larmOverrideV3 = 'larm_override_v3';
const String larmFollowV3Prefix = '${larmFollowV3}_';
const String larmOverrideV3Prefix = '${larmOverrideV3}_';
const String larmArmedV2 = 'larm_armed_v2';
const String larmRangV2 = 'larm_rang_v2';

/// Slider granularity. Volume is stored 0–100 in multiples of ten so the
/// generated `*_vNN.wav` gain variants match what the user sees.
const int volumeStepPercent = 10;

/// Bundled tones are 2.4–4s. `FLAG_INSISTENT` (4) makes Android repeat the
/// channel sound until the notification is cancelled; `timeoutAfter` closes
/// that ring window after the configured duration (default ~10s). A silent
/// summary replaces it so the user can still see that the alarm went off.
const int alarmRingMs = 10 * 1000;
const int insistentNotificationFlag = 4; // Notification.FLAG_INSISTENT

/// Dedicated id for the silent "alarm rang at …" notice posted when the ring
/// window closes. Kept apart from fire ids so the summary survives until tap.
const int rangNotificationId = 0x52414E47;

/// Legacy ids removed during [NotificationService.init].
List<String> legacyChannelIds() => <String>[
      'larm_follow',
      'larm_override_v1',
      larmFollowV2,
      larmOverrideV2,
      larmFollowV3,
      larmOverrideV3,
      for (final sound in alarmSounds)
        if (sound.id != 'system') 'larm_tone_${sound.id}_v2',
    ];

/// Older ids kept here so upgrade cleanup stays readable.
const String larmFollowV2 = 'larm_follow_v2';
const String larmOverrideV2 = 'larm_override_v2';

/// Rounds a stored 0–100 volume to the generated gain bucket. Zero means mute;
/// any positive value maps to 10–100 so the channel always has a valid raw
/// resource even though a muted channel does not play it.
int volumeBucket(int volume) {
  if (volume <= 0) return 0;
  final rounded = ((volume + volumeStepPercent - 1) ~/ volumeStepPercent) *
      volumeStepPercent;
  return rounded.clamp(volumeStepPercent, 100);
}

/// Raw resource for a tone at the current gain bucket. `system` has no bundled
/// asset of its own, so it uses the default tone scaled like every other one.
String rawSoundForVolume(String soundId, int volume) {
  final bucket = volumeBucket(volume);
  final base = (soundId == 'system' || !isKnownSound(soundId))
      ? 'glass_chime'
      : soundId;
  return '${base}_v${bucket == 0 ? volumeStepPercent : bucket}';
}

/// Versioned fire channel id for the selected tone and volume bucket. A new id
/// is required whenever the sound changes: Android never lets an existing
/// channel's sound be rewritten, even after the channel was deleted.
String fireChannelId({
  required bool overrideMode,
  required String soundId,
  required int volume,
}) =>
    '${overrideMode ? larmOverrideV3Prefix : larmFollowV3Prefix}'
    '${rawSoundForVolume(soundId, volume)}';

/// Both fire channels for one Settings snapshot, follow then override.
List<String> fireChannelIds({
  required String soundId,
  required int volume,
}) =>
    [
      fireChannelId(
        overrideMode: false,
        soundId: soundId,
        volume: volume,
      ),
      fireChannelId(
        overrideMode: true,
        soundId: soundId,
        volume: volume,
      ),
    ];

/// Picks the versioned fire channel for a fire. The channel id itself encodes
/// tone + volume because the notification channel's sound cannot be changed.
String channelFor({
  required bool overrideMode,
  required String soundId,
  required int volume,
}) =>
    fireChannelId(
      overrideMode: overrideMode,
      soundId: soundId,
      volume: volume,
    );

/// Fire channel using the generated gain-scaled raw WAV for [volume].
AndroidNotificationChannel fireChannel({
  required String id,
  required String name,
  required String soundId,
  required int volume,
  required bool bypassDnd,
}) {
  final muted = volumeBucket(volume) == 0;
  return AndroidNotificationChannel(
    id,
    name,
    description: muted
        ? 'Alarm and timer alerts. Sound muted in Larm settings.'
        : 'Alarm and timer alerts at ${volumeBucket(volume)}% Larm volume.',
    importance: bypassDnd ? Importance.max : Importance.high,
    playSound: !muted,
    sound: muted
        ? null
        : RawResourceAndroidNotificationSound(
            rawSoundForVolume(soundId, volume),
          ),
    enableVibration: true,
    bypassDnd: bypassDnd,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );
}

/// Silent status/rang channels are static and never replaced.
List<AndroidNotificationChannel> staticChannels() => const [
      AndroidNotificationChannel(
        larmArmedV2,
        'Alarm status',
        description: 'Silent ongoing notice showing the next armed alarm.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
      AndroidNotificationChannel(
        larmRangV2,
        'Alarm rang',
        description: 'Silent reminder that an alarm or timer went off.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
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
/// policy access, requested when the user opts into override). [vibrationId]
/// is the global pattern from Settings, applied to every alarm and timer.
AndroidNotificationDetails alarmDetails({
  required bool overrideMode,
  required String entryId,
  required String payload,
  required String soundId,
  required int volume,
  required String vibrationId,
  int ringMs = alarmRingMs,
}) {
  final channelId = channelFor(
    overrideMode: overrideMode,
    soundId: soundId,
    volume: volume,
  );
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
