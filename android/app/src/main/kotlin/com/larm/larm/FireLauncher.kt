package com.larm.larm

import android.app.Activity
import android.app.ActivityOptions
import android.app.AlarmManager
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
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * App-owned companion alarm for every fire.
 *
 * `flutter_local_notifications` owns the audible notification and its FSI, but
 * Android intentionally skips the FSI while the screen is on and the user is
 * active, and One UI also suppresses it while interactive. The exact alarm
 * wakes a receiver, which starts a short-lived foreground service (allowed by
 * the exact-alarm exception even when Larm is cached/killed). That service
 * starts MainActivity with the notification's SELECT_NOTIFICATION intent, so
 * the existing Flutter callback queues the fire through FireHandoff and
 * deduplicates it against the notification/FSI paths.
 */
object FireLauncher {
    const val CHANNEL = "com.larm.larm/fire_launcher"
    const val ARG_ID = "id"
    const val ARG_AT = "at"
    const val ARG_PAYLOAD = "payload"
    const val ARG_NOTIFICATION_ID = "notificationId"
    const val ARG_BRIDGE_NOTIFICATION_ID = "bridgeNotificationId"
    const val SELECT_ACTION = "SELECT_NOTIFICATION"

    private const val PREFS = "FlutterSharedPreferences"
    private const val PREF_PREFIX = "flutter.fire_launcher."
    private const val LAST_FIRE_AT = "flutter.fire_launcher.last_fire_at"

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "schedule" -> {
                        val id = call.argument<Int>(ARG_ID)
                        val at = call.argument<Long>(ARG_AT)
                        val payload = call.argument<String>(ARG_PAYLOAD)
                        if (id == null || at == null || payload.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "id, at and payload are required", null)
                        } else {
                            schedule(app, id, at, payload)
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
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("FIRE_LAUNCHER", e.message, null)
            }
        }
    }

    fun schedule(context: Context, id: Int, atMillis: Long, payload: String) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val whenMillis = maxOf(atMillis, System.currentTimeMillis() + 50)
        val pi = pendingIntent(context, id, payload)
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
    }

    /** Records the real fire instant so Flutter can cap its fallback tone. */
    fun markFire(context: Context, atMillis: Long) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(LAST_FIRE_AT, atMillis)
            .apply()
    }

    /** True while the ringing notification still owns the looping tone. */
    private fun notificationActive(context: Context, id: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        val manager = context.getSystemService(NotificationManager::class.java) ?: return true
        return manager.activeNotifications.any { it.id == id }
    }

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
                if (at < System.currentTimeMillis() - 60_000) {
                    stale.add(key)
                    continue
                }
                schedule(context, id, at, payload)
            } catch (_: Exception) {
                stale.add(key)
            }
        }
        if (stale.isNotEmpty()) {
            prefs.edit().apply { stale.forEach { remove(it) } }.apply()
        }
    }

    private fun pendingIntent(context: Context, id: Int, payload: String): PendingIntent {
        // A receiver, not an activity: AlarmManager can always wake one, and it
        // can start the bridge foreground service under the exact-alarm
        // exemption. Starting an activity directly is blocked on One UI once
        // Larm has no visible process.
        val intent = Intent(context, FireLaunchBridgeReceiver::class.java).apply {
            putExtra(ARG_NOTIFICATION_ID, id)
            putExtra(ARG_PAYLOAD, payload)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_CANCEL_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, id, intent, flags)
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
        FireLauncher.markFire(context, System.currentTimeMillis())
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
            putExtra(FireLauncher.ARG_BRIDGE_NOTIFICATION_ID, bridgeNotificationId(id))
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
            .notify(bridgeNotificationId(id), notification)
    }

    private fun bridgeNotificationId(id: Int): Int = id xor 0x40000000

    private companion object {
        const val ACTION_BRIDGE = "com.larm.larm.FIRE_BRIDGE"
    }
}

/**
 * Very short foreground service that re-dispatches the notification launch
 * intent to MainActivity. Running as a foreground service gives the activity
 * start a BAL exception even when Larm was killed/cached at fire time.
 */
class FireBridgeService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startBridgeForeground()
        val payload = intent?.getStringExtra(FireLauncher.ARG_PAYLOAD)
        if (!payload.isNullOrEmpty()) {
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
