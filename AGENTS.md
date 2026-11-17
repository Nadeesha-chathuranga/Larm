# Larm

> Flutter alarm + timer app (Android-only MVP), local-only, no auth.
> Scaffolded 2026-09-17 via `flutter create --project-name larm --org com.larm .`.

* Stack (verified M0): Flutter 3.47.4 / Dart 3.13.3, Riverpod 2.6, Hive CE (`hive_ce` + `hive_ce_flutter`) + shared_preferences, `flutter_local_notifications` 22.3.x + `timezone` 0.11.x, `lucide_icons_flutter` 4.0.x, `vibration` (not `vibration_plus`), one Aurora 2.0 dark glass Material 3 theme.
* Product source of truth: `README.md` (UTC-only alarms, UTC dashboard, live timers, full-screen alerts, single dark glass theme, 22 tones). Dev plan: `docs/LARM_DEV_PLAN_v4.md` (M0–M7 + DoD).
* UTC-only: `lib/src/core/time/clock.dart` is the single source of occurrence/format logic; `nextOccurrence(alarm, fromUtc:)`. `isUtc` and `themeMode`/`family` Hive fields are retained for schema stability but ignored by logic/UI. Legacy Local alarms are disabled once on upgrade (`lib/src/core/prefs.dart` keys).
* Theming: `lib/src/core/theme/tokens.dart` defines `larmGlassTheme`, `AuroraBackdrop` (installed globally in `lib/src/app.dart`), `NeonText`, `NeonFab`, `GlassCard`, `GlassIcon`, `GlassPill`. There is no theme/family picker; `family.dart` was deleted. All icons use Lucide.
* Sounds: `lib/src/core/audio/sounds.dart` lists 23 catalog entries (22 bundled + `system`), grouped `Popular`/`General`/`Classic`/`Melodic`/`Ambient`. Regenerate the 10 original Popular WAVs for `assets/sounds/` and Android `res/raw/` with `dart run tools/generate_sounds.dart`. Never rename existing sound ids (Android channels are immutable).
* Entrypoint: `lib/main.dart`. Feature dirs under `lib/src/...` per dev plan — do not invent other roots. Status: M0–M7 done (dashboard, editor, trigger, settings, v2 channels, icon/splash, release APK + Play/QA docs); left: on-device QA matrix + signed upload (see `docs/QA_MATRIX.md`, `docs/PLAY_DECLARATIONS.md`).
* Verify: `flutter analyze`, `flutter test`, single test `flutter test test/time_test.dart --plain-name "<name>"`.
* Widget tests: Hive hangs in fake async — all Hive work inside `tester.runAsync`, `pump()` (never `pumpAndSettle`); test pumps must carry durations (`pump(Duration)`) or route transitions freeze mid-flight inside `runAsync`; full rules in `docs/LARM_DEV_PLAN_v4.md` §2a.
* Working branch is `Nadee01` (vs `main`) — confirm PR target with owner before pushing.
