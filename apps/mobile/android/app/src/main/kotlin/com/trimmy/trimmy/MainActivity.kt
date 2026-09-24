package com.trimmy.trimmy

import android.Manifest
import android.content.pm.PackageManager
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "requestPermission") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    result.success("granted")
                    return@setMethodCallHandler
                }
                if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                    result.success("granted")
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
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) "granted" else "denied",
        )
    }
}
