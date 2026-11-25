# Device QA matrix — Larm Android MVP

> Code-verified items are covered by unit/widget tests (`test/time_test.dart`,
> `test/scheduler_test.dart`, `test/fire_state_test.dart`,
> `test/settings_test.dart`, `test/dashboard_test.dart`, `test/trigger_test.dart`).
> Everything below needs a physical Android 14+ device; emulator coverage is
> partial (no Doze/OEM behavior).

## Automated (done in CI-equivalent `flutter test`)

* [x] Daily/weekday/custom/one-time next-fire, incl. expired → null.
* [x] UTC instant fixed across US DST spring-forward (device zone ignored).
* [x] Legacy `isUtc` flag has no effect; UTC-only dashboard/editor copy.
* [x] Scheduler: stable 31-bit ids, follow/override/tone channel routing,
  snooze math, timer completion, syncAll counts, action parsing.
* [x] 22 bundled tone ids are raw-safe and produce 22 tone channels.
* [x] All `fmtTime`/`fmtUtcTime`/`fmtDateTime` callers are 24-hour only; the
  Settings time-format section is gone and the alarm tone has a preview bar.
* [x] Hour/minute wheel wrap helpers (`23 → 00`, `59 → 00`) and cold-start
  handoff queue, including native-bridge writes and stacked fires.
* [x] Late duplicate fire callbacks do not push a second `/trigger` route; a
  late Stop/Snooze action is delivered to the already-open page instead.
* [x] Code-verified efficiency: no persistent foreground service or background
  polling; the dashboard's 1s ticker stops outside `resumed`, and ring audio /
  timers are disposed at page exit.
* [x] Settings persist `alarmVolume` (0–100) and `ringDurationSec` (5–300,
  default 10); the chosen duration reaches both `timeoutAfter` and the native
  ring-end alarm.
* [x] Snooze metadata and the armed snapshot round-trip through
  SharedPreferences; stale/deleted snoozes are pruned.
* [x] Armed shade body includes a minute-granular UTC countdown and a
  `Snoozed · N left` prefix for snoozed fires.
* [x] Dashboard tiles show the same amber snooze badge; taking a snoozed fire
  consumes one remaining snooze.

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

* [ ] Saving an alarm or starting a timer shows a silent ongoing "Alarm armed"
  notification with the closest UTC fire and a live countdown (`in 5m`,
  `in 2h 7m`, `in <1m`); it clears when neither remains and after the app
  resumes following the last fire. The shade countdown advances while the app
  is killed (native minute ticker).
* [ ] Locked screen + screen off + AOD: full-screen ringing window with rings,
  large alarm name, 24-hour UTC time, Snooze/Cancel — no dashboard flash on a
  cold start.
* [ ] Unlocked + in use: alarm-style heads-up notification sounds/repeats for
  the configured ring duration (default 10s); no app page opens unless the
  notification or an action is tapped.
* [ ] Unlocked + backgrounded: notification-only fire; returning to Larm shows
  the refreshed armed notice, not a stale fired alarm.
* [ ] Silent mode + DND, follow mode: no sound, notification present.
* [ ] Silent mode + DND, override mode (with policy access): sound + bypass.
* [ ] Two alarms same minute: stack as sequential trigger routes; popping
  the top reveals the next.
* [ ] Notification Cancel/Snooze action buttons work from lock shade.
* [ ] A snoozed alarm/timer gets an amber badge in the dashboard's alarm/timer
  section with remaining snoozes and countdown; the "Alarm armed" shade body
  shows the same UTC instant and `Snoozed · N left`.
* [ ] Reaching the configured ring duration without action closes the ringing
  notification and full-screen page; a silent "Alarm rang at HH:mm UTC" notice
  remains until tapped/swiped, and Larm stays minimized.
* [ ] Cancel or Snooze after a fire closes the full-screen page, cancels the
  ringing notification, and leaves Larm minimized — no page reappears.
* [ ] Locked cold start: companion FSI writes the fire to Flutter's pending
  queue and the ringing page is the first visible route.
* [ ] Killed-app notification action opens the page and applies Stop/Snooze
  once, without leaving a second ringing page behind.
* [ ] Killed-app tap on notification opens the trigger page (launch details).
* [ ] Reboot with enabled alarms → fires still occur (boot receiver +
  cold-start resync).
* [ ] One-time alarm Cancel → disabled; legacy repeating alarms convert to their
  next UTC slot on upgrade.
* [x] Earlier build verified (2026-11-25, `SM A536E` / Android 16): screen-off
  killed fires auto-popped and the sound repeated for ~10s. The current build
  narrows the companion bridge to locked/screen-off only, so the unlocked cases
  above need a fresh pass. Do not use `am force-stop` for fire QA — it cancels
  both AlarmManager schedules on this Samsung build; use Recents swipe or
  `am kill`.

## Manual — time behavior

* [ ] Travel across timezones: dashboard clock and every alarm time stay in
  UTC; editor preview shows the same UTC instant regardless of device zone.
* [ ] DST transition weekend: daily UTC alarm keeps its fixed instant.
* [ ] Timer completes with app killed (scheduled completion, not ticker).

## Manual — appearance + tones

* [ ] Dashboard, editor, trigger and settings all show the compact pure-black
  glass theme with dark inward-glow cards; no light/system theme picker or
  12/24-hour option remains.
* [ ] Android navigation bar stays visible on every route; the last alarm card
  and the `+` button are not covered, and the ringing popup is inset above it.
* [ ] New alarm window order is title → time wheels → date → UTC time-zone
  card; the larger hour/minute wheels loop `23 → 00` and `59 → 00`.
* [ ] Lucide icons and the subtle hero UTC hint are legible on small screens;
  every displayed time uses 24-hour `HH:mm`.
* [ ] Settings is single-level and the Alarm tone section has a named preview
  bar with a play button, a real 0–100% alarm-volume slider, and a
  `System alarm volume` shortcut. The slider scales previews, the in-app
  fallback ring, and the gain-scaled raw tone used by the Android fire channel.
* [ ] `Ringing duration` slider offers 5–300s and defaults to 10s; changing it
  reschedules enabled alarms/timers.
* [ ] All 10 Popular tones preview in-app and play through their notification
  channels when used as the global alarm tone.
* [x] Earlier build verified (2026-11-25): fire sound repeated for ~10s via
  `Notification.FLAG_INSISTENT` and stopped when `timeoutAfter` cancelled the
  notification (`RingtonePlayer` 11:06:44.8 → 11:06:54.1 after a killed,
  screen-off fire). Bundled tones are only 2.4–4s, so looping is required. If
  an OEM cancels the notification early, `TriggerPage` continues the global
  tone in-app for the remainder of the 10s window.
* [x] Volume fix verified on device (2026-11-25): tapping the slider from 50% to
  90% moved the Flutter value and replaced the fire channels from
  `larm_follow_v3_pulse_ring_v50` to `larm_follow_v3_pulse_ring_v90`, with the
  channel sound URI changing from `pulse_ring_v50` to `pulse_ring_v90`
  (`dumpsys notification --noredact`). The old channels were marked deleted.
* [ ] Changing the tone/vibration in Settings applies to every alarm and timer;
  the editor shows no per-alarm sound or vibration controls.

## Device findings (2026-11-25, `SM A536E` / Android 16)

* `flutter_local_notifications` 22.3.3 does **not** auto-register
  `ScheduledNotificationReceiver`; without the explicit manifest `<receiver>`
  entry the OS delivered the schedule broadcast but no notification was posted.
  Fixed in `android/app/src/main/AndroidManifest.xml`.
* Full-screen intent permission was already granted. While the screen was on
  and the user was interactive, Samsung showed only the alarm heads-up; the OS
  FSI was not invoked. The revised build now treats that heads-up as the
  intended unlocked presentation and gates the companion bridge to
  locked/screen-off fires only (`PowerManager.isInteractive` +
  `KeyguardManager.isDeviceLocked`).
* Android 16 blocked a direct launch with `BAL_BLOCK`; the companion
  PendingIntent uses `ActivityOptions.setPendingIntentCreatorBackgroundActivityStartMode(
  MODE_BACKGROUND_ACTIVITY_START_ALLOWED)`. A foreground service alone no
  longer grants a general activity-start exception; the silent companion FSI
  is the supported locked-screen path from a killed/cached app, and it now
  persists the fire in Flutter's pending queue so a cold start shows `/trigger`
  first.
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
* [x] `flutter analyze`, full `flutter test`, and `flutter build apk --debug`
  pass after the screen-aware fire / compact UI changes (2026-11-25).
* [x] `flutter analyze`, full `flutter test`, and `flutter build apk --debug`
  pass after the volume / snooze visibility / ring-duration / countdown /
  auto-close changes (2026-11-25).
* [ ] Complete the revised on-device QA pass above on `RZCW100088D` (USB
  debugging is authorized and the debug APK installs; new fire behavior not yet
  exercised on device).
* [ ] Sign with upload key, fill Play declarations (`PLAY_DECLARATIONS.md`).
