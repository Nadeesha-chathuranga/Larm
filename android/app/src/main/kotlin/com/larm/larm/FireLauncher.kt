package com.larm.larm

import android.app.Activity
import android.app.ActivityOptions
import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Locked-screen companion alarm for every fire.
 *
 * `flutter_local_notifications` owns the audible notification and its FSI.
 * While the phone is unlocked and in use, that heads-up notification is the
 * intended presentation and this bridge exits immediately. When the screen is
 * off or the keyguard is locked, the exact alarm wakes a receiver which adds
 * a silent FSI fallback; Android never accepts a plain activity start from a
 * cached/killed app. FireHandoff deduplicates the OS and companion paths.
 */
object FireLauncher {
    const val CHANNEL = "com.larm.larm/fire_launcher"
    const val ARG_ID = "id"
    const val ARG_AT = "at"
    const val ARG_PAYLOAD = "payload"
    const val ARG_RING_MS = "ringMs"
    const val ARG_AT_MILLIS = "atMillis"
    const val ARG_NOTIFICATION_ID = "notificationId"
    const val ARG_BRIDGE_NOTIFICATION_ID = "bridgeNotificationId"
    const val SELECT_ACTION = "SELECT_NOTIFICATION"

    const val PREFS = "FlutterSharedPreferences"
    private const val PREF_PREFIX = "flutter.fire_launcher."
    private const val LAST_FIRE_AT = "flutter.fire_launcher.last_fire_at"

    // SharedPreferences keys are stored in the Flutter file with this prefix.
    // Writing here lets a native FSI fallback hand the fire to FireHandoff even
    // when the Flutter isolate has not started yet.
    private const val PENDING_FIRES = "flutter.pending_fires_v1"
    private const val MAX_PENDING_FIRES = 20

    // Status notifications written by Flutter's SharedPreferences wrapper.
    const val ARMED_SNAPSHOT = "flutter.armed_snapshot_v1"
    private const val ARMED_CHANNEL_ID = "larm_armed_v2"
    private const val RANG_CHANNEL_ID = "larm_rang_v2"
    private const val ARMED_NOTIFICATION_ID = 0x4C41524D
    private const val RANG_NOTIFICATION_ID = 0x52414E47
    private const val ARMED_TICK_REQUEST = 0x41524D54
    private const val RING_END_REQUEST_OFFSET = 0x10000000
    private const val DEFAULT_RING_MS = 10_000L

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        val activity = context as? Activity
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "schedule" -> {
                        val id = call.argument<Int>(ARG_ID)
                        val at = call.argument<Long>(ARG_AT)
                        val payload = call.argument<String>(ARG_PAYLOAD)
                        val ringMs = call.argument<Int>(ARG_RING_MS)?.toLong()
                            ?: DEFAULT_RING_MS
                        if (id == null || at == null || payload.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "id, at and payload are required", null)
                        } else {
                            schedule(app, id, at, payload, ringMs)
                            result.success(true)
                        }
                    }
                    "cancel" -> {
                        val id = call.argument<Int>(ARG_ID)
                        if (id == null) {
                            result.error("INVALID_ARGS", "id is required", null)
                        } else {
                            cancel(app, id)
                            result.success(true)
                        }
                    }
                    "isNotificationActive" -> {
                        val id = call.argument<Int>(ARG_ID)
                        if (id == null) {
                            result.error("INVALID_ARGS", "id is required", null)
                        } else {
                            result.success(notificationActive(app, id))
                        }
                    }
                    "finishRing" -> {
                        val id = call.argument<Int>(ARG_ID)
                        val payload = call.argument<String>(ARG_PAYLOAD)
                        val at = call.argument<Long>(ARG_AT_MILLIS)
                        if (id == null || payload.isNullOrEmpty() || at == null) {
                            result.error("INVALID_ARGS", "id, payload and atMillis are required", null)
                        } else {
                            completeRing(app, id, payload, at)
                            result.success(true)
                        }
                    }
                    "scheduleArmedTick" -> {
                        val at = call.argument<Long>(ARG_AT)
                        if (at == null) {
                            result.error("INVALID_ARGS", "at is required", null)
                        } else {
                            scheduleArmedTick(app, at)
                            result.success(true)
                        }
                    }
                    "cancelArmedTick" -> {
                        cancelArmedTick(app)
                        result.success(true)
                    }
                    "minimize" -> result.success(activity?.moveTaskToBack(true) ?: false)
                    "openAlarmVolumeSettings" -> {
                        openSoundSettings(app)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("FIRE_LAUNCHER", e.message, null)
            }
        }
    }

    fun schedule(
        context: Context,
        id: Int,
        atMillis: Long,
        payload: String,
        ringMs: Long = DEFAULT_RING_MS,
    ) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val whenMillis = maxOf(atMillis, System.currentTimeMillis() + 50)
        val pi = pendingIntent(context, id, payload, ringMs)
        val exact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
        if (exact) {
            alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(whenMillis, pi), pi)
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMillis, pi)
        }
    }

    fun cancel(context: Context, id: Int) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        alarmManager.cancel(pendingIntent(context, id, ""))
        alarmManager.cancel(ringEndPendingIntent(context, id, "", 0L))
    }

    /// Schedules the ring-window close from the actual fire instant, so a late
    /// launch does not shorten the audible ring. The notification's own
    /// `timeoutAfter` is the primary timer; this receiver adds the summary.
    fun scheduleRingEnd(context: Context, id: Int, payload: String, atMillis: Long) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val whenMillis = maxOf(atMillis, System.currentTimeMillis() + 50)
        val pi = ringEndPendingIntent(context, id, payload, whenMillis)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMillis, pi)
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, whenMillis, pi)
        }
    }

    /// Called by Flutter when the user stopped/snoozed the fire: no second
    /// summary may appear after the ring-end alarm was cancelled.
    fun completeRing(context: Context, id: Int, payload: String, atMillis: Long) {
        cancelRingEnd(context, id)
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.cancel(id)
        manager.cancel(bridgeNotificationId(id))
        showRangSummary(context, payload, atMillis)
    }

    private fun cancelRingEnd(context: Context, id: Int) {
        context.getSystemService(AlarmManager::class.java)
            ?.cancel(ringEndPendingIntent(context, id, "", 0L))
    }

    /**
     * Only force the ringing page when the user cannot see the notification.
     * While the phone is unlocked and in use, the alarm notification's own
     * heads-up (with its looping tone) is the intended presentation.
     */
    fun shouldOpenFullScreen(context: Context): Boolean {
        val interactive = context.getSystemService(PowerManager::class.java)?.isInteractive ?: true
        val locked = context.getSystemService(KeyguardManager::class.java)?.isDeviceLocked ?: false
        return !interactive || locked
    }

    /** Records the real fire instant so Flutter can cap its fallback tone. */
    fun markFire(context: Context, atMillis: Long) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(LAST_FIRE_AT, atMillis)
            .apply()
    }

    /**
     * Queues a locked-screen bridge fire for Flutter's [FireHandoff]. The JSON
     * shape matches `PendingFire.decode`, so a cold start consumes it as the
     * first `/trigger` route instead of flashing the dashboard.
     */
    fun recordPendingFire(context: Context, payload: String) {
        val separator = payload.indexOf(':')
        if (separator <= 0 || separator == payload.length - 1) return
        val kind = payload.substring(0, separator)
        if (kind != "alarm" && kind != "timer") return
        val encoded = JSONObject()
            .put("kind", kind)
            .put("id", payload.substring(separator + 1))
            .toString()
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getStringSet(PENDING_FIRES, emptySet<String>())
            ?: emptySet<String>()
        if (existing.contains(encoded)) return
        val updated = (existing + encoded).toList()
            .takeLast(MAX_PENDING_FIRES)
            .toSet()
        prefs.edit().putStringSet(PENDING_FIRES, updated).apply()
    }

    /** True while the ringing notification still owns the looping tone. */
    private fun notificationActive(context: Context, id: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        val manager = context.getSystemService(NotificationManager::class.java) ?: return true
        return manager.activeNotifications.any { it.id == id }
    }

    /// One inexact minute ticker refreshes the armed shade countdown without
    /// keeping a Dart isolate (or a foreground service) alive.
    fun scheduleArmedTick(context: Context, atMillis: Long) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val now = System.currentTimeMillis()
        val nextMinute = now - (now % 60_000L) + 60_000L
        alarmManager.setInexactRepeating(
            AlarmManager.RTC,
            minOf(nextMinute, atMillis),
            60_000L,
            armedTickPendingIntent(context),
        )
    }

    fun cancelArmedTick(context: Context) {
        context.getSystemService(AlarmManager::class.java)
            ?.cancel(armedTickPendingIntent(context))
    }

    /// Updates the same notification id the Flutter plugin uses for "armed",
    /// so Dart's next `refreshArmed` cleanly takes ownership back.
    fun showArmedTick(context: Context, label: String, atMillis: Long) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        ensureSilentChannel(context, ARMED_CHANNEL_ID, "Alarm status")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, ARMED_CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Alarm armed")
            .setContentText("$label · ${countdownLabel(atMillis - System.currentTimeMillis())}")
            .setContentIntent(openAppPendingIntent(context, ARMED_NOTIFICATION_ID))
            .setCategory(Notification.CATEGORY_STATUS)
            .setPriority(Notification.PRIORITY_LOW)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .build()
        manager.notify(ARMED_NOTIFICATION_ID, notification)
    }

    /// Replaces a finished ring with a silent notice. It stays in the shade
    /// until tapped/swiped, so the user still sees that the alarm went off.
    private fun showRangSummary(context: Context, payload: String, atMillis: Long) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        ensureSilentChannel(context, RANG_CHANNEL_ID, "Alarm rang")
        val title = if (payload.startsWith("timer:")) "Timer rang" else "Alarm rang"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, RANG_CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText("$title at ${formatUtc(atMillis)} UTC")
            .setContentIntent(openAppPendingIntent(context, RANG_NOTIFICATION_ID))
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_LOW)
            .setAutoCancel(true)
            .setOngoing(false)
            .setOnlyAlertOnce(true)
            .build()
        manager.notify(RANG_NOTIFICATION_ID, notification)
    }

    private fun ensureSilentChannel(context: Context, id: String, name: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(id) != null) return
        manager.createNotificationChannel(
            NotificationChannel(id, name, NotificationManager.IMPORTANCE_LOW).apply {
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            },
        )
    }

    private fun countdownLabel(remainingMillis: Long): String {
        if (remainingMillis <= 0) return "now"
        val minutes = remainingMillis / 60_000L
        if (minutes < 1) return "in <1m"
        val hours = minutes / 60
        return if (hours > 0) {
            "in ${hours}h ${minutes % 60}m"
        } else {
            "in ${minutes}m"
        }
    }

    private fun formatUtc(millis: Long): String {
        val format = SimpleDateFormat("HH:mm", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date(millis))
    }

    private fun openAppPendingIntent(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    private fun armedTickPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, ArmedTickReceiver::class.java)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, ARMED_TICK_REQUEST, intent, flags)
    }

    private fun openSoundSettings(context: Context) {
        val intent = Intent(Settings.ACTION_SOUND_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    fun bridgeNotificationId(id: Int): Int = id xor 0x40000000

    /** Restores companion alarms after boot/update from Flutter's prefs file. */
    fun rescheduleStored(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stale = mutableListOf<String>()
        for ((key, value) in prefs.all) {
            if (!key.startsWith(PREF_PREFIX) || value !is String) continue
            try {
                val json = JSONObject(value)
                val id = json.getInt(ARG_ID)
                val at = json.getLong(ARG_AT)
                val payload = json.getString(ARG_PAYLOAD)
                val ringMs = if (json.has(ARG_RING_MS)) {
                    json.getInt(ARG_RING_MS).toLong()
                } else {
                    DEFAULT_RING_MS
                }
                if (at < System.currentTimeMillis() - 60_000) {
                    stale.add(key)
                    continue
                }
                schedule(context, id, at, payload, ringMs)
            } catch (_: Exception) {
                stale.add(key)
            }
        }
        if (stale.isNotEmpty()) {
            prefs.edit().apply { stale.forEach { remove(it) } }.apply()
        }
    }

    private fun pendingIntent(
        context: Context,
        id: Int,
        payload: String,
        ringMs: Long = DEFAULT_RING_MS,
    ): PendingIntent {
        // A receiver, not an activity: AlarmManager can always wake one, and it
        // can start the bridge foreground service under the exact-alarm
        // exemption. Starting an activity directly is blocked on One UI once
        // Larm has no visible process.
        val intent = Intent(context, FireLaunchBridgeReceiver::class.java).apply {
            putExtra(ARG_NOTIFICATION_ID, id)
            putExtra(ARG_PAYLOAD, payload)
            putExtra(ARG_RING_MS, ringMs.toInt())
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_CANCEL_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, id, intent, flags)
    }

    private fun ringEndPendingIntent(
        context: Context,
        id: Int,
        payload: String,
        atMillis: Long,
    ): PendingIntent {
        val intent = Intent(context, RingEndReceiver::class.java).apply {
            putExtra(ARG_NOTIFICATION_ID, id)
            putExtra(ARG_PAYLOAD, payload)
            putExtra(ARG_AT_MILLIS, atMillis)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(
            context,
            id xor RING_END_REQUEST_OFFSET,
            intent,
            flags,
        )
    }
}

/// Refreshes the armed shade notice once a minute from the snapshot Dart
/// writes next to its other SharedPreferences values.
class ArmedTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val raw = context.getSharedPreferences(FireLauncher.PREFS, Context.MODE_PRIVATE)
            .getString(FireLauncher.ARMED_SNAPSHOT, null)
            ?: return
        try {
            val json = JSONObject(raw)
            val at = json.getLong("at")
            val label = json.getString("label")
            if (at > System.currentTimeMillis()) {
                FireLauncher.showArmedTick(context, label, at)
            }
        } catch (_: Exception) {
            // A malformed snapshot is ignored; the next Dart refresh rewrites it.
        }
    }
}

/// Closes the ringing notification after the configured duration and leaves a
/// silent summary so the user can still see that the alarm went off.
class RingEndReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val id = intent?.getIntExtra(FireLauncher.ARG_NOTIFICATION_ID, -1) ?: -1
        val payload = intent?.getStringExtra(FireLauncher.ARG_PAYLOAD)
        val at = intent?.getLongExtra(FireLauncher.ARG_AT_MILLIS, 0L) ?: 0L
        if (id < 0 || payload.isNullOrEmpty() || at <= 0) return
        FireLauncher.completeRing(context, id, payload, at)
    }
}

/**
 * Wakes Larm at the exact fire instant and hands off to a foreground service.
 * Kept separate from the service because receivers cannot show UI themselves.
 */
class FireLaunchBridgeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val payload = intent?.getStringExtra(FireLauncher.ARG_PAYLOAD)
        if (payload.isNullOrEmpty()) return
        val id = intent.getIntExtra(FireLauncher.ARG_NOTIFICATION_ID, -1)
        val firedAt = System.currentTimeMillis()
        FireLauncher.markFire(context, firedAt)
        val ringMs = intent.getIntExtra(FireLauncher.ARG_RING_MS, 10_000).toLong()
        if (id >= 0) {
            FireLauncher.scheduleRingEnd(context, id, payload, firedAt + ringMs)
        }
        if (!FireLauncher.shouldOpenFullScreen(context)) return
        FireLauncher.recordPendingFire(context, payload)
        val launch = Intent(context, FireBridgeService::class.java).apply {
            action = ACTION_BRIDGE
            putExtra(FireLauncher.ARG_NOTIFICATION_ID, id)
            putExtra(FireLauncher.ARG_PAYLOAD, payload)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(launch)
        } else {
            context.startService(launch)
        }
        // The FGS activity start is still blocked on Android 16 when Larm has
        // no visible window. A system-sent FSI is the supported exception.
        showFullScreenBridge(context, id, payload)
    }

    private fun showFullScreenBridge(context: Context, id: Int, payload: String) {
        val channelId = "larm_fire_fsi_v2"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(channelId) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(channelId, "Alarm full screen", NotificationManager.IMPORTANCE_HIGH)
                        .apply {
                            setSound(null, null)
                            enableVibration(false)
                        },
                )
            }
        }
        val launch = Intent(context, FireLaunchActivity::class.java).apply {
            action = FireLauncher.SELECT_ACTION
            putExtra(FireLauncher.ARG_NOTIFICATION_ID, id)
            putExtra(FireLauncher.ARG_PAYLOAD, payload)
            putExtra(
                FireLauncher.ARG_BRIDGE_NOTIFICATION_ID,
                FireLauncher.bridgeNotificationId(id),
            )
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        // Android 15+ requires the PendingIntent creator to delegate its BAL
        // privilege. Without this, SystemUI's FSI launch is blocked too.
        val options = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ActivityOptions.makeBasic()
                .setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                )
                .toBundle()
        } else {
            null
        }
        val fsi = PendingIntent.getActivity(context, id, launch, flags, options)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Alarm")
            .setContentText("Alarm is ringing")
            .setContentIntent(fsi)
            .setFullScreenIntent(fsi, true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_HIGH)
            .setOngoing(true)
            .setTimeoutAfter(1500)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(FireLauncher.bridgeNotificationId(id), notification)
    }

    private companion object {
        const val ACTION_BRIDGE = "com.larm.larm.FIRE_BRIDGE"
    }
}

/**
 * Very short foreground service that retries the activity handoff. Android 16
 * no longer treats an FGS as a general background-activity exception, so the
 * companion FSI above is the supported path when Larm has no visible window.
 */
class FireBridgeService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startBridgeForeground()
        val payload = intent?.getStringExtra(FireLauncher.ARG_PAYLOAD)
        if (!payload.isNullOrEmpty() && FireLauncher.shouldOpenFullScreen(this)) {
            FireLauncher.recordPendingFire(this, payload)
            val launch = Intent(this, MainActivity::class.java).apply {
                action = FireLauncher.SELECT_ACTION
                putExtra(
                    FireLauncher.ARG_NOTIFICATION_ID,
                    intent.getIntExtra(FireLauncher.ARG_NOTIFICATION_ID, -1),
                )
                putExtra(FireLauncher.ARG_PAYLOAD, payload)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            try {
                // The foreground service above is itself a BAL exception, so no
                // extra ActivityOptions opt-in is needed here.
                startActivity(launch)
            } catch (_: Exception) {
                // The notification/FSI path may already have opened the page.
            }
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf(startId)
        return START_NOT_STICKY
    }

    private fun startBridgeForeground() {
        val channelId = "larm_fire_bridge"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(channelId) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(channelId, "Alarm bridge", NotificationManager.IMPORTANCE_LOW)
                        .apply {
                            setSound(null, null)
                            enableVibration(false)
                        },
                )
            }
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Alarm")
            .setContentText("Opening alarm")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                1,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE,
            )
        } else {
            startForeground(1, notification)
        }
    }
}

/** Legacy direct-launch bridge, kept for alarms scheduled by older builds. */
class FireLaunchActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val bridgeId = intent.getIntExtra(FireLauncher.ARG_BRIDGE_NOTIFICATION_ID, -1)
        if (bridgeId >= 0) {
            getSystemService(NotificationManager::class.java).cancel(bridgeId)
        }
        dispatch()
        finish()
        overridePendingTransition(0, 0)
    }

    private fun dispatch() {
        val payload = intent.getStringExtra(FireLauncher.ARG_PAYLOAD)
        if (payload.isNullOrEmpty()) return
        FireLauncher.recordPendingFire(this, payload)
        val id = intent.getIntExtra(FireLauncher.ARG_NOTIFICATION_ID, -1)
        if (id >= 0) {
            FireLauncher.scheduleRingEnd(
                this,
                id,
                payload,
                System.currentTimeMillis() + 10_000L,
            )
        }
        val launch = Intent(this, MainActivity::class.java).apply {
            action = FireLauncher.SELECT_ACTION
            putExtra(
                FireLauncher.ARG_NOTIFICATION_ID,
                intent.getIntExtra(FireLauncher.ARG_NOTIFICATION_ID, -1),
            )
            putExtra(FireLauncher.ARG_PAYLOAD, payload)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(launch)
    }
}

/** Re-arms companion launch alarms after reboot or package replacement. */
class FireLaunchBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        FireLauncher.rescheduleStored(context)
    }
}
