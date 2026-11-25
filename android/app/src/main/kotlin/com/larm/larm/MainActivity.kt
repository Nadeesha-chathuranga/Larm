package com.larm.larm

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FireLauncher.register(flutterEngine.dartExecutor.binaryMessenger, this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FSI_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                "openFullScreenIntentSettings" -> {
                    result.success(openFullScreenIntentSettings())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return true
        }
        val manager = getSystemService(NotificationManager::class.java)
        return manager.canUseFullScreenIntent()
    }

    /// Opens the Android 14+ full-screen intent setting for this app. The FLAG
    /// keeps the setting reachable even if the caller was a background isolate.
    private fun openFullScreenIntentSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                .setData(Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private companion object {
        const val FSI_CHANNEL = "com.larm.larm/fsi"
    }
}
