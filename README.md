# Larm

Larm — a UTC-only alarm &amp; timer app for gaming groups across timezones. Every alarm fires at its UTC instant and the dashboard shows only UTC time, so there's no ambiguity when travelling or coordinating across regions. Pick a UTC date and time for each one-time alarm, run live timers, see countdowns, and get full-screen alerts that respect your phone's sound settings. A single pure-black dark glass theme uses restrained cyan/white accents, frosted panels and clear Lucide icons for maximum contrast. No login required — just open and go.

## Highlights

- **UTC only, 24-hour only** — no device-local clock, local alarm mode, or 12-hour toggle; every screen shows UTC in `HH:mm`.
- **One-time alarms** — choose the exact UTC date with a custom in-app calendar; no repeat modes. The hour and minute wheels loop (`23 → 00`, `59 → 00`).
- **One sound, one vibration** — pick a tone and vibration pattern once in Settings; a preview bar plays the selected tone. Every alarm and timer uses them. The tone bar includes an in-app volume slider and a shortcut to Android's alarm volume.
- **Configurable ring duration** — choose how long a fire keeps ringing (5–300s, default 10s). When the window ends, the ringing notification/full-screen page closes and a silent "Alarm rang at HH:mm UTC" notice remains until tapped.
- **Snooze you can see** — snoozed alarms and timers show an amber badge with the remaining snoozes and live countdown; the notification shade shows the same UTC time and remaining count.
- **Pure-black glass** — one true-black theme with dark inward-glow cards, crisp glass edges and a high-contrast UTC clock.
- **22 bundled tones** — 12 original classics plus 10 royalty-free "Popular" tones synthesized locally (`dart run tools/generate_sounds.dart`).
- **Live timers and screen-aware alerts** — alarms and timers keep running after the app is killed. Unlocked fires are alarm-style heads-up notifications with looping sound; locked/screen-off fires open the full-screen ringing page. A silent ongoing "Alarm armed" notice shows the closest armed alarm or timer with a live minute countdown, and disappears when none remain. Stopping, snoozing, or letting a fire finish leaves Larm minimized. All UI stays above the Android navigation bar.
- **Local-only, no auth** — all data stays on the device.
