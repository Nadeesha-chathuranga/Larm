/// SharedPreferences keys used across app startup and UI.
const String utcMigrationKey = 'utc_migration_v1';

/// Set when legacy Local alarms were disabled, so the dashboard can explain.
const String legacyLocalDisabledKey = 'legacy_local_disabled';

/// Set once repeating alarms have been converted to one-time UTC alarms.
const String oneTimeMigrationKey = 'one_time_migration_v1';
