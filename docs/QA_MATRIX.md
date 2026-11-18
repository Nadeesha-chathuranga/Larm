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
* [ ] Changing the tone/vibration in Settings applies to every alarm and timer;
  the editor shows no per-alarm sound or vibration controls.

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
