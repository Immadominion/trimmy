package com.trimmy.trimmy

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.time.ZoneId

class MainActivity : FlutterActivity() {
    companion object {
        private const val notificationChannel = "com.trimmy.trimmy/notifications"
        private const val notificationRequest = 7401
        private const val deviceTimeZoneChannel = "com.trimmy.trimmy/device_timezone"
    }

    private var pendingNotificationResult: MethodChannel.Result? = null
    private var reminders: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (intent?.getBooleanExtra(ReminderSchedule.OPEN_CAREER, false) == true) {
            ReminderSchedule.recordOpen(this)
            intent.removeExtra(ReminderSchedule.OPEN_CAREER)
        }
        reminders = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannel)
        reminders!!.setMethodCallHandler { call, result ->
                if (call.method == "consumeOpenCareer") {
                    result.success(ReminderSchedule.consumeOpen(this))
                    return@setMethodCallHandler
                }
                if (call.method == "setReminder") {
                    val preference = call.argument<String>("preference")
                    if (preference !in setOf("daily", "occasional", "off")) {
                        result.error("INVALID_FREQUENCY", "Choose a reminder frequency.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(ReminderSchedule.replace(this, preference!!))
                    } catch (_: Exception) {
                        result.error("SCHEDULE_FAILED", "The reminder could not be scheduled.", null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "requestPermission") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    result.success(if (ReminderSchedule.allowed(this)) "granted" else "denied")
                    return@setMethodCallHandler
                }
                if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                    result.success(if (ReminderSchedule.allowed(this)) "granted" else "denied")
                    return@setMethodCallHandler
                }
                if (pendingNotificationResult != null) {
                    result.error("REQUEST_PENDING", "A notification request is already open.", null)
                    return@setMethodCallHandler
                }
                pendingNotificationResult = result
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationRequest)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceTimeZoneChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "getTimeZoneId") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    result.success(ZoneId.systemDefault().id)
                } catch (error: Exception) {
                    result.error("TIME_ZONE_UNAVAILABLE", error.message, null)
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(ReminderSchedule.OPEN_CAREER, false)) {
            ReminderSchedule.recordOpen(this)
            intent.removeExtra(ReminderSchedule.OPEN_CAREER)
            reminders?.invokeMethod("openCareer", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationRequest) return
        val result = pendingNotificationResult ?: return
        pendingNotificationResult = null
        result.success(
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && ReminderSchedule.allowed(this)) "granted" else "denied",
        )
    }
}
