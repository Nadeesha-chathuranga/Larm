/// SharedPreferences keys used across app startup and UI.
const String utcMigrationKey = 'utc_migration_v1';

/// Set when legacy Local alarms were disabled, so the dashboard can explain.
const String legacyLocalDisabledKey = 'legacy_local_disabled';

/// Set once repeating alarms have been converted to one-time UTC alarms.
const String oneTimeMigrationKey = 'one_time_migration_v1';

/// Fires waiting for the Flutter navigator to open the ringing page.
const String pendingFiresKey = 'pending_fires_v1';

/// Recently shown fires, used to suppress late duplicate callbacks (FSI,
/// notification tap and exact-alarm bridge can all report the same fire).
const String recentFiresKey = 'recent_fires_v1';

/// Prefix for persisted native launch alarms (native adds Flutter's `flutter.`
/// SharedPreferences prefix). One entry per fire id for boot recovery.
const String fireLauncherKeyPrefix = 'fire_launcher.';

/// Snoozed fires: JSON map keyed by `alarm:<id>` / `timer:<id>` with the next
/// snooze fire instant and remaining snoozes.
const String snoozedFiresKey = 'snoozed_fires_v1';

/// Compact snapshot of the closest armed fire, read by the native minute ticker
/// so the notification can show a live countdown without starting Dart.
const String armedSnapshotKey = 'armed_snapshot_v1';
