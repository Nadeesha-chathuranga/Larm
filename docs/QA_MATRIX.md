# Device QA matrix — Larm Android MVP

> Code-verified items are covered by unit tests (`test/time_test.dart`,
> `test/scheduler_test.dart`). Everything below needs a physical Android 14+
> device; emulator coverage is partial (no Doze/OEM behavior).

## Automated (done in CI-equivalent `flutter test`)

* [x] Daily/weekday/custom/one-time next-fire, incl. expired → null.
* [x] UTC instant fixed across US DST spring-forward (device zone ignored).
* [x] Legacy `isUtc` flag has no effect; UTC-only dashboard/editor copy.
* [x] Scheduler: stable 31-bit ids, follow/override/tone channel routing,
  snooze math, timer completion, syncAll counts, action parsing.
* [x] 22 bundled tone ids are raw-safe and produce 22 tone channels.
* [x] Late duplicate fire callbacks do not push a second `/trigger` route; a
  late Stop/Snooze action is delivered to the already-open page instead.

## Manual — permissions (Android 14+, fresh install)

* [ ] POST_NOTIFICATIONS prompt appears when saving/enabling first alarm.
* [ ] Exact alarms are auto-granted via `USE_EXACT_ALARM`; "Exact alarms off"
  banner stays hidden. If an OEM forces it off, the inexact fallback still
  schedules and the banner/deep link remains available.
* [ ] Save/toggle with notifications denied → warning snackbar, alarm still
  persisted and rescheduled when permission is restored.
* [ ] FSI revoked (Settings → Apps → Larm → Notifications → full-screen off)
  → fire shows heads-up; tap opens in-app trigger page.
* [ ] Battery-opt prompt appears in Enable flow; denying keeps banner.

## Manual — firing

* [ ] Saving an alarm shows a silent ongoing "Alarm armed" notification in the
  shade with the next UTC fire time; it disappears when the last alarm/timer
  is disabled or deleted.
* [ ] Locked screen + screen off + AOD: full-screen trigger window with rings,
  large alarm name, UTC time, Snooze/Cancel.
* [ ] Silent mode + DND, follow mode: no sound, notification present.
* [ ] Silent mode + DND, override mode (with policy access): sound + bypass.
* [ ] Two alarms same minute: stack as sequential trigger routes; popping
  the top reveals the next.
* [ ] Notification Cancel/Snooze action buttons work from lock shade.
* [x] FSI auto-pop: alarm fires while app killed → ringing page appears
  without tapping the notification (verified 2026-11-25, screen off + killed,
  `SM A536E` / Android 16). Note: `am force-stop` cancels both AlarmManager
  schedules on this Samsung build; use Recents swipe or `am kill` instead.
* [x] FSI auto-pop: alarm fires while app backgrounded → ringing page is
  pushed automatically over the previous route (verified 2026-11-25, screen on
  + backgrounded).
* [x] FSI auto-pop: alarm fires while app is foregrounded → ringing page is
  pushed automatically (verified 2026-11-25, `SM A536E` / Android 16). Samsung
  suppresses the OS FSI while interactive, so `FireLauncher` schedules a
  companion exact alarm that re-dispatches `SELECT_NOTIFICATION`; its
  PendingIntent opts into background activity starts (`FLAG_INSISTENT` for
  sound is separate). No notification tap is needed.
* [ ] Killed-app notification action opens the page and applies Stop/Snooze
  once, without leaving a second ringing page behind.
* [ ] Killed-app tap on notification opens the trigger page (launch details).
* [ ] Reboot with enabled alarms → fires still occur (boot receiver +
  cold-start resync).
* [ ] One-time alarm Cancel → disabled; legacy repeating alarms convert to their
  next UTC slot on upgrade.

## Manual — time behavior

* [ ] Travel across timezones: dashboard clock and every alarm time stay in
  UTC; editor preview shows the same UTC instant regardless of device zone.
* [ ] DST transition weekend: daily UTC alarm keeps its fixed instant.
* [ ] Timer completes with app killed (scheduled completion, not ticker).

## Manual — appearance + tones

* [ ] Dashboard, editor, trigger and settings all show the pure-black glass
  theme with dark inward-glow cards; no light/system theme picker remains.
* [ ] Lucide icons and the subtle hero UTC hint are legible on small screens;
  alarm tiles have no UTC badge.
* [ ] All 10 Popular tones preview in-app and play through their notification
  channels when used as the global alarm tone.
* [x] Fire sound repeats for ~10s via `Notification.FLAG_INSISTENT` and stops
  when `timeoutAfter` cancels the notification; the ringing page remains for
  Snooze/Cancel (verified 2026-11-25: `RingtonePlayer` start 11:06:44.8 → stop
  11:06:54.1 after a killed/screen-off fire). Bundled tones are only 2.4–4s, so
  looping is required. If an OEM cancels the notification early, `TriggerPage`
  continues the global tone in-app for the remainder of the 10s window.
* [ ] Changing the tone/vibration in Settings applies to every alarm and timer;
  the editor shows no per-alarm sound or vibration controls.

## Device findings (2026-11-25, `SM A536E` / Android 16)

* `flutter_local_notifications` 22.3.3 does **not** auto-register
  `ScheduledNotificationReceiver`; without the explicit manifest `<receiver>`
  entry the OS delivered the schedule broadcast but no notification was posted.
  Fixed in `android/app/src/main/AndroidManifest.xml`.
* Full-screen intent permission was already granted. While the screen was on
  and the user was interactive, Samsung showed only the alarm heads-up; the OS
  FSI was not invoked. `FireLauncher` now provides the direct pop path.
* Android 16 blocked the first direct launch with `BAL_BLOCK`; the companion
  PendingIntent now uses `ActivityOptions.setPendingIntentCreatorBackgroundActivityStartMode(
  MODE_BACKGROUND_ACTIVITY_START_ALLOWED)`. A foreground service alone no
  longer grants a general activity-start exception; the silent companion FSI
  is the supported path from a killed/cached app.
* The OS alarm, its FSI and the companion exact alarm can all report the same
  fire seconds apart. A 90-second persisted dedupe window now suppresses the
  late duplicates that previously stacked two `/trigger` routes; Stop/Snooze
  actions arriving late are delivered to the open page via a broadcast stream.
  Verified 2026-11-25: one Cancel closes the ringing page after a killed fire.

## Manual — upgrade + scale

* [ ] Install M1 build (v1 channels), upgrade: v1 channels deleted, v2 set
  created, alarms intact.
* [ ] Upgrade a build with enabled Local alarms: one-time UTC notice appears,
  those alarms are off, and no Local label is shown anywhere.
* [ ] 100+ alarms enabled: only next occurrence each is pending
  (`pendingNotificationRequests` well under the ~500 OEM cap).

## Release

* [x] `flutter build apk --release` succeeds (2026-11-18: 58.1MB, debug-signed).
* [ ] Sign with upload key, fill Play declarations (`PLAY_DECLARATIONS.md`).
