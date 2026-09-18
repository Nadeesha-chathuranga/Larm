# Larm

> Flutter alarm + timer app (Android-only MVP), local-only, no auth.
> Scaffolded 2026-09-17 via `flutter create --project-name larm --org com.larm .`.

* Stack (verified M0): Flutter 3.47.4 / Dart 3.13.3, Riverpod 2.6, Hive CE (`hive_ce` + `hive_ce_flutter`) + shared_preferences, `flutter_local_notifications` 22.3.x + `timezone` 0.11.x / `flutter_timezone`, `vibration` (not `vibration_plus`), Material 3 B&W + 6-theme pack.
* Product source of truth: `README.md` (minimalist B&W, local + UTC alarms, live timers, full-screen alerts). Dev plan: `docs/LARM_DEV_PLAN_v4.md` (M0–M7 + DoD).
* Entrypoint: `lib/main.dart`. Feature dirs under `lib/src/...` per dev plan — do not invent other roots. Status: M0–M7 done (dashboard, editor, trigger, settings, v2 channels, icon/splash, release APK + Play/QA docs); left: on-device QA matrix + signed upload (see `docs/QA_MATRIX.md`, `docs/PLAY_DECLARATIONS.md`).
* Verify: `flutter analyze`, `flutter test`, single test `flutter test test/time_test.dart --plain-name "<name>"`.
* Widget tests: Hive hangs in fake async — all Hive work inside `tester.runAsync`, `pump()` (never `pumpAndSettle`); test pumps must carry durations (`pump(Duration)`) or route transitions freeze mid-flight inside `runAsync`; full rules in `docs/LARM_DEV_PLAN_v4.md` §2a.
* Working branch is `Nadee01` (vs `main`) — confirm PR target with owner before pushing.
