# Device QA matrix — Larm Android MVP

> Code-verified items are covered by unit tests (`test/time_test.dart`,
> `test/scheduler_test.dart`). Everything below needs a physical Android 14+
> device; emulator coverage is partial (no Doze/OEM behavior).

## Automated (done in CI-equivalent `flutter test`)

* [x] Daily/weekday/custom/one-time next-fire, incl. expired → null.
* [x] UTC instant fixed across US DST spring-forward; local wall kept.
* [x] Local vs UTC diverge correctly on travel day.
* [x] Scheduler: stable 31-bit ids, follow/override/tone channel routing,
  snooze math, timer completion, syncAll counts, action parsing.

## Manual — permissions (Android 14+, fresh install)

* [ ] POST_NOTIFICATIONS prompt appears when enabling first alarm.
* [ ] Deny exact alarms → banner "Exact alarms off" shows; alarms still
  saved; re-tap Enable → system exact-alarm settings deep link.
* [ ] FSI revoked (Settings → Apps → Larm → Notifications → full-screen off)
  → fire shows heads-up; tap opens in-app trigger page.
* [ ] Battery-opt prompt appears in Enable flow; denying keeps banner.

## Manual — firing

* [ ] Locked screen + screen off + AOD: full-screen trigger page with rings,
  title, time, Snooze/Stop.
* [ ] Silent mode + DND, follow mode: no sound, notification present.
* [ ] Silent mode + DND, override mode (with policy access): sound + bypass.
* [ ] Two alarms same minute: stack as sequential trigger routes; popping
  the top reveals the next.
* [ ] Notification Stop/Snooze action buttons work from lock shade.
* [ ] Killed-app tap on notification opens the trigger page (launch details).
* [ ] Reboot with enabled alarms → fires still occur (boot receiver +
  cold-start resync).
* [ ] Repeating alarm Stop → next occurrence scheduled; one-time Stop →
  disabled.

## Manual — time behavior

* [ ] Travel across timezones: local alarm keeps wall time, UTC alarm keeps
  instant (compare dashboard hero + editor preview).
* [ ] DST transition weekend: daily local alarm still fires at wall time.
* [ ] Timer completes with app killed (scheduled completion, not ticker).

## Manual — upgrade + scale

* [ ] Install M1 build (v1 channels), upgrade: v1 channels deleted, v2 set
  created, alarms intact.
* [ ] 100+ alarms enabled: only next occurrence each is pending
  (`pendingNotificationRequests` well under the ~500 OEM cap).

## Release

* [x] `flutter build apk --release` succeeds (M7: 63.6MB, debug-signed).
* [ ] Sign with upload key, fill Play declarations (`PLAY_DECLARATIONS.md`).
