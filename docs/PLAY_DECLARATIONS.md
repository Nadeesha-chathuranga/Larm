# Play Console declarations — Larm (com.larm.larm)

> Fill these into Play Console on first release. Verified against the current
> release APK (`aapt2 dump permissions` shows all eight permissions merged).

## 1. Exact alarms (`USE_EXACT_ALARM` + `SCHEDULE_EXACT_ALARM`)

* Where: Policy declarations → Exact alarm permission.
* Declare: core functionality **is** alarms/timers. Larm schedules user-set
  alarms and timers via `AlarmManager.setAlarmClock`
  (`AndroidScheduleMode.alarmClock`); inexact delivery would break the app's
  sole purpose.
* `USE_EXACT_ALARM` is auto-granted on Android 13+ for qualifying alarm apps.
  Larm qualifies (its only function is user-set alarms/timers), so exact
  firing does not depend on a user permission state some OEMs fail to surface.
* `SCHEDULE_EXACT_ALARM` is declared only for Android 12 and older
  (`android:maxSdkVersion="32"`), so a device never sees both permissions.
  On Android 13+ the exact-alarm settings deep link is only a fallback. If
  exact scheduling is ever unavailable, the app retries with
  `inexactAllowWhileIdle` and shows a "may delay" banner.

## 2. Full-screen intent (`USE_FULL_SCREEN_INTENT`)

* Where: Policy declarations → Full-screen intent permission (required since
  2024-05-31).
* Declare: alarm-clock core function. The permission wakes the screen with
  the ringing page (`fullScreenIntent: true`, high/max importance channel,
  `showWhenLocked` + `turnScreenOn` activity attributes). Revocation path is
  handled: heads-up notification + in-app full-screen page.

## 3. Data safety section

* Data collected: **none**. No accounts, no network calls, no analytics.
  Alarms/timers/settings live in on-device Hive boxes; all 22 tones are
  bundled, royalty-free assets. Alerts are scheduled in UTC using the bundled
  timezone database for notifications only — no device location or network
  lookup is used.
* Permissions rationale (user-facing, for the store listing):
  * Exact alarms — fire at the set time.
  * Full-screen intent — show the ringing screen over lock.
  * Notifications — deliver alerts.
  * Boot completed — restore alarms after reboot.
  * Vibration / wake lock — ring + vibrate.
  * Ignore battery optimizations — requested once, in-context, so OEM
    battery savers don't kill overnight alarms.

## 4. Pre-launch checklist

* [ ] Target SDK = current Flutter stable mapping (check `flutter doctor`).
* [ ] App must request POST → exact → FSI → battery-opt in that order
  (dashboard Enable flow); screenshots for review if requested.
* [ ] Release signed with the upload key (M7 APK uses debug signing —
  configure `key.properties` before first upload).
