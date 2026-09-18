# Larm v4 — Dev-Ready Spec (Android-only, complete build)

> Locked: Flutter 3.47.4 / Dart 3.13.3 on `Nadee01`, Android-only MVP,
> `SCHEDULE_EXACT_ALARM`, two-channel DND, hybrid analog+digital hero,
> B&W-first + 6-theme pack, modern motion.
> Repo: greenfield (`README`, `LICENSE`, `AGENTS.md` only) at time of writing.
> Product truth: `README.md`. Workflow truth: `AGENTS.md`.

## 0. Conventions

* Root: `C:\Users\Admin\Documents\GitHub\Larm`, branch `Nadee01`
* Style: `flutter_lints` strict, files `lower_snake_case`, features own folders
* Every step ends with `flutter analyze`
* Tests: `flutter test <path>`, single test: `flutter test test/time_test.dart --plain-name "<name>"`
* State: `flutter_riverpod ^2.6`
* Nav: `Navigator 2.0` via `MaterialApp.routes` (`/`, `/editor`, `/trigger`, `/settings`).
  If `go_router` preferred later, swap in M1 with same route names.

## 1. Dependencies (`pubspec.yaml`)

```yaml
dependencies:
  flutter_riverpod: ^2.6.1
  hive_ce: ^2.19.3
  hive_ce_flutter: ^2.3.4
  shared_preferences: ^2.3.0
  flutter_local_notifications: ^22.3.0
  timezone: ^0.11.1
  flutter_timezone: ^5.1.0   // v5: TimezoneInfo.identifier; v2 broke release (Kotlin JVM 1.8)
  permission_handler: ^12.0.0
  audioplayers: ^6.1.0
  vibration: ^3.2.0
  intl: ^0.20.0
  uuid: ^4.6.0
  animations: ^2.0.11
  flutter_animate: ^4.5.0
  rive: ^0.13.0
  lottie: ^3.1.0
  google_fonts: ^6.2.0
dev_dependencies:
  flutter_lints: ^6.0.0
  build_runner: ^2.4.0
  hive_ce_generator: ^1.11.3
  flutter_launcher_icons: ^0.14.0
  flutter_native_splash: ^2.4.0
```

## 2. File map (create in order)

```text
lib/main.dart
lib/src/app.dart
lib/src/core/time/clock.dart
lib/src/core/nav.dart
lib/src/core/notifications/service.dart
lib/src/core/notifications/scheduler.dart
lib/src/core/notifications/background_handler.dart
lib/src/core/notifications/channels.dart
lib/src/core/theme/family.dart
lib/src/core/theme/tokens.dart
lib/src/core/audio/sounds.dart
lib/src/core/haptics.dart
lib/src/core/motion.dart
lib/src/core/nav.dart
lib/src/data/models/alarm.dart
lib/src/data/models/larm_timer.dart
lib/src/data/models/settings.dart
lib/src/data/repos/alarm_repo.dart
lib/src/data/repos/timer_repo.dart
lib/src/data/repos/settings_repo.dart
lib/src/features/dashboard/dashboard_page.dart
lib/src/features/dashboard/widgets/hybrid_hero.dart
lib/src/features/dashboard/widgets/analog_painter.dart
lib/src/features/dashboard/widgets/alarm_tile.dart   // also TimerTile + repeatLabel
lib/src/features/editor/editor_page.dart
lib/src/features/editor/widgets/wheel_picker.dart
lib/src/features/editor/widgets/sound_sheet.dart
lib/src/features/trigger/trigger_page.dart
lib/src/features/trigger/widgets/pulse_rings.dart
lib/src/features/settings/settings_page.dart
assets/sounds/{mono_beep,glass_chime,digital_beacon,soft_wake,radar_pulse,zen_bowl}.mp3
assets/rive/bell.riv
assets/icon/logo.svg
test/time_test.dart
test/scheduler_test.dart
test/dashboard_test.dart
test/editor_test.dart
test/trigger_test.dart
test/settings_test.dart
test/widget_test.dart   // boots LarmApp; shares dashboardScope helper
android/app/src/main/AndroidManifest.xml
```

## 2a. Test rules (learned M3 — do not regress)

* Hive does all file IO with real async: `openBox`/`put`/`delete` HANG
  inside `testWidgets` fake async. Wrap Hive setup + pumps + taps in
  `tester.runAsync`. Never use `pumpAndSettle` (analog ticker runs forever).
* Route transitions (push/pop, OpenContainer, entrances) run on the fake
  clock: test pumps must carry durations (`pump(Duration)`) even inside
  `runAsync`, or taps land on frozen mid-transition layouts (e.g. a slide
  frozen 75% shifts content +200px). `spin()` helpers pump real delays AND
  fake durations together.
* Split-brain pattern for gesture tests: Hive work in `runAsync`, swipe
  physics in the fake zone (`tester.drag` + `pump(Duration)`), then back to
  `runAsync` for repo assertions. Implicit animations (snackbar entrance)
  only advance on the fake clock.
* Widget tests bypass `main()`: call `tz.initializeTimeZones()` +
  `tz.setLocalLocation(tz.UTC)` in the scope helper.
* `AlarmRepeat` (not `RepeatMode`): Flutter already exports `RepeatMode`.
* `plugin.initialize(settings:)` and `plugin.cancel(id:)` are named args in
  notifications 22.x; exact status is `canScheduleExactNotifications()`
  (no `canScheduleExactAlarms`); `box.listenable()` lives in
  `hive_ce_flutter`, not `hive_ce`.
* `tearDownAll` uses 10s-timeout resilient `Hive.close()` + dir delete:
  close has been observed to stall on Windows after gesture tests.

## 3. Data schemas (Hive typeId 0,1,2)

```dart
// alarm.dart — typeId 0
@HiveType(typeId: 0)
class Alarm {
  @HiveField(0) String id;              // uuid v4
  @HiveField(1) String title;           // trim, max 60, empty -> "Alarm"
  @HiveField(2) bool isUtc;             // false = Local wall-time
  @HiveField(3) int hour;               // 0-23
  @HiveField(4) int minute;             // 0-59
  @HiveField(5) int? year;              // oneTime only
  @HiveField(6) int? month;
  @HiveField(7) int? day;
  @HiveField(8) RepeatMode repeat;      // oneTime,daily,weekdays,custom
  @HiveField(9) List<bool> days;        // len 7, Mon=0
  @HiveField(10) bool enabled;
  @HiveField(11) String soundId;
  @HiveField(12) String vibId;
  @HiveField(13) DateTime createdAtUtc;
}

// larm_timer.dart — typeId 1
{
  id: String, title: String,
  durationSec: int (>0), remainingSec: int,
  status: idle|running|paused|done,
  targetUtc: DateTime?, enabled: bool
}

// settings.dart — typeId 2, single box key 'app'
{
  soundMode: follow|override (default follow),
  snoozeMin: 1-30 (default 5),
  snoozeCount: 0-10 (default 3),
  themeMode: system|light|dark (default system),
  family: mono|midnight|arctic|forest|ember|ocean (default mono),
  timeFormat: h12|h24 (default h12),
  defaultSoundId: glass_chime
}
```

Local vs UTC semantics:

* Local: store wall-time + IANA zone (`tz.local`), schedule via `TZDateTime` — respects DST.
* UTC: store absolute UTC instant, schedule that instant regardless of `tz.local`.

## 4. Theme tokens (`core/theme/family.dart`)

Each family defines `lightScheme` + `darkScheme` (`ColorScheme`) + `clockHands`, `ring`, `flipBg`.
Painters read `Theme.of(context)` only — no hardcoded B&W.

| family   | light bg/fg        | dark bg/fg         | accent    |
|----------|--------------------|--------------------|-----------|
| mono     | `#FFFFFF`/`#0A0A0A` | `#000000`/`#F5F5F5` | gray scale |
| midnight | `#F2F5FF`/`#060913` | `#000000`/`#DCE6FF` | `#8AB4FF` |
| arctic   | `#FAFCFE`/`#1B2733` | `#0E151D`/`#E6EEF5` | `#9FB8CC` |
| forest   | `#F6FAF6`/`#0B1510` | `#060D0A`/`#D2E8D5` | `#7ED49A` |
| ember    | `#FFFBF5`/`#221206` | `#140C04`/`#FFE6C4` | `#FFB454` |
| ocean    | `#F4FAFF`/`#071522` | `#040D16`/`#CDEBFF` | `#4FD1FF` |

Rive/Lottie stay monochrome, tinted via `ColorFilter.mode(scheme.onSurface)` so they match any family.
Contrast target ≥ 4.5:1. No per-alarm themes, no custom picker in MVP.

## 5. API contracts

```dart
// core/time/clock.dart
DateTime localNow();
DateTime utcNow();
String fmtTime(DateTime dt, TimeFormat f); // h12 "08:05 PM", h24 "20:05"
TZDateTime nextOccurrence(Alarm a, {required DateTime fromLocal});
TZDateTime utcToZoned(DateTime utc);
TZDateTime localToZoned(int y, int mo, int d, int h, int mi);

// core/notifications/service.dart
Future<void> initNotifications({required BgCallback cb});
Future<void> scheduleAlarm(Alarm a);
Future<void> cancelAlarm(String id);
Future<void> scheduleTimerCompletion({required String id, required DateTime targetUtc, required String title});
Future<void> rescheduleAllOnBoot();
Future<bool> canExact();
Future<void> requestExact();
Future<bool> canFSI();
Future<void> requestFSI();

// core/notifications/background_handler.dart
@pragma('vm:entry-point')
void onBgAction(NotificationResponse r); // actions: stop_<id>, snooze_<id>
// Runs in separate isolate: no singletons, no UI access, top-level only.

// repos
Stream<List<Alarm>> watchAll();
Alarm? getById(String id);
Future<void> upsert(Alarm a);      // persists + schedules/cancels
Future<void> delete(String id);    // + 5s undo buffer in UI
Future<void> toggleEnabled(String id, bool on);
```

## 6. Android + channels + permissions

Manifest snippet (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
```

Do NOT declare `USE_EXACT_ALARM` (Play audit risk). Use `SCHEDULE_EXACT_ALARM`.

Channels (`core/notifications/channels.dart`):

* `larm_follow` — `Importance.default`, system sound, respects DND (default).
* `larm_override_v1` — `Importance.max`, `bypassDnd:true`, system sound placeholder.
* M6 migration: create `larm_follow_v2` / `larm_override_v2` with
  `RawResourceAndroidNotificationSound('mono_beep' …)`, migrate, delete v1.
  Reason: Android channels are immutable after creation.

Permission order (in-context, not all at launch):

1. `POST_NOTIFICATIONS`
2. exact → `canScheduleExactNotifications()` / `requestExactAlarmsPermission()`
   (`Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM`),
   listen `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` → reschedule
3. FSI → no plugin status query; `requestFullScreenIntentPermission()`,
   degrade to HUN + in-app page when revoked
4. battery-opt education (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`)
5. DND-access (`requestNotificationPolicyAccess`) only when user opts into
   `alwaysOverride`

Denied path: inexact fallback + persistent banner "alarms may delay".
Scheduling: `zonedSchedule` with `AndroidScheduleMode.alarmClock`
(`AlarmManager.setAlarmClock` — highest priority, status-bar icon, fires through Doze).

M6 channel design (Android routes sound per channel, not per notification):
`larm_follow_v2` (system/default) + `larm_tone_<id>_v2` ×6 with
`RawResourceAndroidNotificationSound` (raw assets in
`android/app/src/main/res/raw/`) + single `larm_override_v2`
(`bypassDnd`, max, alarm usage). Override is reliability-first: bypass is
guaranteed, per-alarm tone sacrificed. v1 ids deleted at init (immutable).

Routes: `/` dashboard, `/editor?alarmId?`, `/trigger?fireId`, `/settings`.

## 7. Motion spec

* Hero digits: `AnimatedSwitcher` 250ms slide-Y; analog hands: `Ticker` lerp 60fps;
  countdown ring: 500ms easeOut. `RepaintBoundary` around clocks.
* List: `AnimatedList` 300ms + `flutter_animate` stagger 40ms fade+slide;
  `Switch` 180ms scale bounce + `Vibration.vibrate(duration:10)`.
* Nav: FAB → editor `OpenContainer` 350ms; settings `SharedAxis` 300ms.
* Wheels: magnification 1.15, haptic tick on snap.
* Trigger: pulsing rings `repeat` 1800ms expand+fade; Rive bell loop while ringing.
* Respect `MediaQuery.disableAnimations`. 48dp targets, TalkBack labels.

## 8. Build phases (small steps, each ends `flutter analyze`)

### M0 — Scaffold (1-6)

1. `flutter create --project-name larm --org com.larm .` in-place
2. Add deps (section 1) to `pubspec.yaml`
3. Add dev deps + strict `analysis_options.yaml`; create
   `assets/sounds/`, `assets/rive/`, `assets/icon/` + `logo.svg`
4. `flutter pub get` — resolve conflicts
5. `flutter analyze` — 0 issues
6. `flutter test` — empty suite passes

### M1 — Foundations (7-12)

7. `lib/main.dart`: `ensureInitialized` → `tz.initializeTimeZones()` →
   `FlutterTimezone.getLocalTimezone()` → `setLocalLocation` → Hive init →
   notification init + register `onBgAction`
8. `core/time/clock.dart` per section 5
9. Hive models + `dart run build_runner build -d` codegen
10. Riverpod repos per section 5
11. `app.dart`: Material3 B&W + 6 families + `google_fonts` numerals
12. Verify: `flutter analyze`, `flutter test test/time_test.dart`

### M2 — Permissions + Scheduler (13-19)

13. Manifest permissions (section 6)
14. `NotificationService` + `larm_follow` / `larm_override_v1`
15. Permission chain in order (section 6) with explainer sheets
16. `zonedSchedule(AlarmClock)`, `cancel`, boot reschedule, state-change listener
17. Denied fallback + banner; Samsung 500 guard (schedule next occurrence only)
18. Unique IDs for simultaneous fires (queue UI in M5)
19. Verify (manual, Android 14+ device — not unit-testable):
    grant → fires ±1s locked; deny → banner; reboot → refires; FSI off → HUN fallback

### M3 — Dashboard hybrid hero (20-25)

20. `hybrid_hero.dart` + `analog_painter.dart`: analog + digital flip + UTC chip tap-swap +
    next-alarm countdown ring, all from `colorScheme`
21. `alarm_tile.dart`: `LOCAL`/`UTC` badge, repeat label, Switch bounce+haptic
22. `timer_tile.dart`: ticker + Pause/Resume/Reset
23. `AnimatedList` + stagger, `Dismissible` + 5s undo, tap → `/editor`
24. FAB → **stub** editor via `OpenContainer`; empty-state Lottie tinted
25. Verify: `flutter analyze`, `flutter test test/widget_dashboard_test.dart`, DevTools 60fps

### M4 — Editor (26-31)

26. `editor_page.dart` replaces stub: `Alarm|Timer` segment + animated indicator
27. Title field (trim, max 60, empty → "Alarm")
28. `Local|UTC` toggle + live conversion preview (e.g. "08:00 UTC = 13:30 local")
29. `wheel_picker.dart`: 3× `ListWheelScrollView`, magnification, haptic, analog preview rotation
30. Repeat chips `oneTime|daily|weekdays|custom[7]`; sound/vibration pickers with animated preview
31. Save → persist + schedule/cancel; timers also schedule `targetUtc`.
    Verify: `flutter test test/time_test.dart --plain-name "UTC fixed across DST"`,
    manual tz-travel (Local shifts, UTC fixed)

### M5 — Trigger (32-35)

32. `trigger_page.dart`: pulsing rings + Rive bell (tinted), title/time scale-in
33. Snooze (`now + snoozeMin`, enforce `snoozeCount`) + Cancel (reschedule if repeating)
34. Sequential queue UI for simultaneous fires (unique IDs from M2)
35. Verify (manual): locked/off/AOD, silent vs override channels

### M6 — Themes + Settings + Assets (36-42)

36. `family.dart` + `tokens.dart`: 6 families × light/dark per section 4
37. `settings_page.dart`: sound mode (DND prompt only on opt-in), snooze steppers with
    roll anim, theme mode + family preview cards with morph, h12/h24, default sound
38. Bundle 6 royalty-free tones (no iOS-copy names) → `*_v2` channels, migrate, delete v1
39. `flutter_launcher_icons` + `flutter_native_splash` (B&W bell/clock mark)
40. Reduce-motion + TalkBack + contrast sweep
41. Verify: `flutter analyze`, `flutter test test/repos_test.dart`, family × mode sweep
42. Update `AGENTS.md` with real entrypoint (`lib/main.dart`), feature dirs,
    `flutter analyze` / `flutter test` / single-test form

### M7 — QA + Release (43-46)

> M7 build fixes (verified): `android/app/build.gradle.kts` needs
> `isCoreLibraryDesugaringEnabled = true` +
> `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`
> (required by flutter_local_notifications), else
> `:app:checkReleaseAarMetadata` fails. M7 APK: 63.6MB, debug-signed —
> configure `key.properties` before upload. Docs: `docs/QA_MATRIX.md`,
> `docs/PLAY_DECLARATIONS.md`.

43. Matrix: DST change, tz travel, reboot, DND/silent 4-combos, simultaneous fires,
    500-cap (only next scheduled), battery-opt education shown
44. `flutter build apk --release` smoke on device
45. Play declarations drafted: FSI + exact-alarm justification (alarm core)
46. Final: `flutter analyze`, `flutter test`

## 9. Risks / gotchas

* Channels immutable → v1→v2 migration required (covered M2→M6).
* `flutter create .` in non-empty dir needs `--project-name larm` (dir `Larm` is not snake_case).
* Exact + FSI need physical Android 14+ device — emulators/CI insufficient.
* Background handler: top-level + `@pragma('vm:entry-point')`, no Riverpod/static access.
* OEM killers: education prompt required; `dontkillmyapp` guidance for test devices.
* Tones must be royalty-free recreations — do not ship Apple/Google copies.
